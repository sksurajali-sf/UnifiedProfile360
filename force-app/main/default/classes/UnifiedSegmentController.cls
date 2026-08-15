/**
 * Segments a unified profile belongs to.
 *
 * Data Cloud writes one segment membership table per Identity Resolution ruleset, shared by
 * every segment built on it, and names it with an org-specific numeric suffix
 * (ssotIndividualMc_Unified_SMH_178239085__dlm). The suffix is never guessed: the table name is
 * read from MarketSegment.SegmentMembershipTable, so the same package works in any org.
 *
 * The shape of that table is what keeps this affordable at a thousand segments. Membership is
 * one query filtered by the profile, not one query per segment, and the query service collapses
 * the publish history to the newest row per segment before anything reaches Apex.
 */
public with sharing class UnifiedSegmentController {
    /** A profile in more segments than this is capped; the newest memberships are kept. */
    private static final Integer MAX_SEGMENTS = 200;
    private static final Integer MAX_TABLES = 4;
    private static final Pattern SAFE_NAME = Pattern.compile('^[A-Za-z0-9_]+$');

    /** Delta type on the newest row when the profile has dropped out of a segment. */
    private static final Set<String> EXITED = new Set<String>{
        'removed',
        'remove',
        'deleted',
        'delete',
        'exited',
        'exit',
        'dropped'
    };

    public class SegmentRow implements Comparable {
        @AuraEnabled
        public String segmentId;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String status;
        @AuraEnabled
        public String publishStatus;
        @AuraEnabled
        public Datetime lastPublished;
        @AuraEnabled
        public Datetime nextPublish;
        @AuraEnabled
        public String schedule;
        @AuraEnabled
        public String publishType;
        @AuraEnabled
        public String segmentType;
        @AuraEnabled
        public Long memberCount;
        /** When this profile was last written into the segment's membership. */
        @AuraEnabled
        public Datetime memberSince;
        @AuraEnabled
        public Boolean isNewMember;

        /** Most recently published first, undated last, then by name. */
        public Integer compareTo(Object other) {
            SegmentRow that = (SegmentRow) other;
            if (lastPublished != that.lastPublished) {
                if (lastPublished == null) {
                    return 1;
                }
                if (that.lastPublished == null) {
                    return -1;
                }
                return that.lastPublished > lastPublished ? 1 : -1;
            }
            if (name == that.name) {
                return 0;
            }
            if (name == null) {
                return 1;
            }
            return that.name == null ? -1 : name.compareTo(that.name);
        }
    }

    public class SegmentResult {
        @AuraEnabled
        public List<SegmentRow> segments = new List<SegmentRow>();
        /** True when the profile has more memberships than were read. */
        @AuraEnabled
        public Boolean truncated = false;
        @AuraEnabled
        public String notice;
    }

    /** ConnectApi rules out cacheable=true, so the panel loads once per page view. */
    @AuraEnabled
    public static SegmentResult getSegments(String recordId, String objectApiName) {
        SegmentResult result = new SegmentResult();

        String unifiedId = UnifiedProfileController.resolveUnifiedIdFor(recordId, objectApiName);
        if (String.isBlank(unifiedId)) {
            return result;
        }

        UnifiedProfileRegistry.DmoSet dmo = UnifiedProfileRegistry.resolve(objectApiName);
        List<String> tables = membershipTables(dmo.segmentTablePrefix, dmo.prefix);
        if (tables.isEmpty()) {
            result.notice = 'No published segments are built on ' + dmo.unifiedIndividual + '.';
            return result;
        }

        Map<String, Membership> memberships = readMemberships(tables, unifiedId, dmo.dataSpace);
        if (memberships.isEmpty()) {
            return result;
        }
        result.truncated = memberships.size() >= MAX_SEGMENTS;

        Set<Id> segmentIds = new Set<Id>();
        for (String raw : memberships.keySet()) {
            try {
                segmentIds.add(Id.valueOf(raw));
            } catch (Exception e) {
                // A membership row pointing at something that is not a segment id is skipped.
                continue;
            }
        }
        if (segmentIds.isEmpty()) {
            return result;
        }

        result.segments = describeSegments(
            [
                SELECT
                    Id,
                    Name,
                    SegmentStatus,
                    PublishStatus,
                    LastPublishedEndDateTime,
                    NextPublishDateTime,
                    PublishScheduleInterval,
                    PublishScheduleInfo,
                    PublishType,
                    MarketSegmentType,
                    LastSegmentMemberCount
                FROM MarketSegment
                WHERE Id IN :segmentIds
                WITH USER_MODE
                LIMIT 200
            ],
            memberships
        );

        result.segments.sort();
        return result;
    }

    /** Segment metadata joined to this profile's membership in each one. */
    @TestVisible
    private static List<SegmentRow> describeSegments(
        List<MarketSegment> segments,
        Map<String, Membership> memberships
    ) {
        List<SegmentRow> rows = new List<SegmentRow>();
        for (MarketSegment s : segments) {
            // Membership rows carry the 15 character id, so both forms are tried.
            Membership m = memberships.get(String.valueOf(s.Id));
            if (m == null) {
                m = memberships.get(String.valueOf(s.Id).substring(0, 15));
            }

            SegmentRow row = new SegmentRow();
            row.segmentId = s.Id;
            row.name = s.Name;
            row.status = prettify(s.SegmentStatus);
            row.publishStatus = prettify(s.PublishStatus);
            row.lastPublished = s.LastPublishedEndDateTime;
            row.nextPublish = s.NextPublishDateTime;
            row.schedule = scheduleLabel(s.PublishScheduleInfo, s.PublishScheduleInterval);
            row.publishType = prettify(s.PublishType);
            row.segmentType = prettify(s.MarketSegmentType);
            row.memberCount = s.LastSegmentMemberCount;
            row.memberSince = m == null ? null : m.since;
            row.isNewMember = m != null && m.isNew;
            rows.add(row);
        }
        return rows;
    }

    @TestVisible
    private class Membership {
        @TestVisible
        Datetime since;
        @TestVisible
        Boolean isNew = false;
    }

    /**
     * Distinct membership tables for this ruleset. An aggregate query, so the cost does not grow
     * with the number of segments in the org.
     */
    @TestVisible
    private static List<String> membershipTables(String prefix, String spacePrefix) {
        List<String> tables = new List<String>();
        if (String.isBlank(prefix)) {
            return tables;
        }

        /*
         * Underscores are single character wildcards in LIKE, so they are escaped to keep one
         * ruleset's tables from matching another's.
         *
         * Two spellings are tried. Segment membership tables in the default space carry no data
         * space prefix (Individual_Unified_SMH_1779366689783__dlm), and no org to hand has
         * segments in a renamed space to say whether that holds there too. Naming both forms
         * covers it without the loose leading wildcard that would let one space's tables answer
         * for another's, which matters because every space can hold an unsuffixed ruleset and
         * those would otherwise be indistinguishable.
         */
        String bare = prefix.replace('_', '\\_') + '%';
        String prefixed = String.isBlank(spacePrefix)
            ? bare
            : spacePrefix.replace('_', '\\_') + bare;
        try {
            for (AggregateResult a : [
                SELECT SegmentMembershipTable tbl
                FROM MarketSegment
                WHERE SegmentMembershipTable LIKE :bare OR SegmentMembershipTable LIKE :prefixed
                WITH USER_MODE
                GROUP BY SegmentMembershipTable
                LIMIT :MAX_TABLES
            ]) {
                String name = String.valueOf(a.get('tbl'));
                if (String.isNotBlank(name) && SAFE_NAME.matcher(name).matches()) {
                    tables.add(name);
                }
            }
        } catch (Exception e) {
            return tables;
        }
        return tables;
    }

    /**
     * Newest membership row per segment. The window function runs in the query service, so a
     * segment republished nightly for a year still returns one row rather than 365.
     */
    @TestVisible
    private static Map<String, Membership> readMemberships(
        List<String> tables,
        String unifiedId,
        String dataSpace
    ) {
        Map<String, Membership> memberships = new Map<String, Membership>();
        String member = '\'' + String.escapeSingleQuotes(unifiedId).replace('\'', '\'\'') + '\'';

        for (String table : tables) {
            String sql =
                'SELECT Segment_Id__c, Delta_Type__c, Timestamp__c FROM (' +
                ' SELECT Segment_Id__c, Delta_Type__c, Timestamp__c,' +
                ' ROW_NUMBER() OVER (PARTITION BY Segment_Id__c ORDER BY Timestamp__c DESC) rn' +
                ' FROM ' +
                table +
                ' WHERE Id__c = ' +
                member +
                ') WHERE rn = 1 ORDER BY Timestamp__c DESC LIMIT ' +
                MAX_SEGMENTS;

            try {
                ConnectApi.CdpQueryInput input = new ConnectApi.CdpQueryInput();
                input.sql = sql;
                ConnectApi.CdpQueryOutputV2 output = UnifiedProfileRegistry.runQuery(input, dataSpace);
                if (output.data == null || output.metadata == null) {
                    continue;
                }

                Integer idAt = columnAt(output.metadata, 'Segment_Id__c');
                Integer deltaAt = columnAt(output.metadata, 'Delta_Type__c');
                Integer timeAt = columnAt(output.metadata, 'Timestamp__c');
                if (idAt < 0) {
                    continue;
                }

                List<List<Object>> rows = new List<List<Object>>();
                for (Integer i = 0; i < output.data.size(); i++) {
                    rows.add(output.data[i].rowData);
                }
                collectMemberships(memberships, rows, idAt, deltaAt, timeAt);
            } catch (Exception e) {
                // One unreadable table should not empty the panel.
                continue;
            }
        }
        return memberships;
    }

    /**
     * The newest row per segment, minus the ones saying the profile has left. A row whose delta
     * type marks an exit is a membership that ended, not one to show.
     */
    @TestVisible
    private static void collectMemberships(
        Map<String, Membership> memberships,
        List<List<Object>> rows,
        Integer idAt,
        Integer deltaAt,
        Integer timeAt
    ) {
        for (List<Object> row : rows) {
            String segmentId = valueAt(row, idAt);
            if (String.isBlank(segmentId)) {
                continue;
            }

            String delta = valueAt(row, deltaAt);
            if (String.isNotBlank(delta) && EXITED.contains(delta.trim().toLowerCase())) {
                continue;
            }

            Membership m = new Membership();
            m.since = parseTimestamp(valueAt(row, timeAt));
            m.isNew = 'new'.equalsIgnoreCase(delta);
            memberships.put(segmentId, m);
        }
    }

    private static Integer columnAt(Map<String, ConnectApi.CdpQueryMetadataItem> metadata, String column) {
        for (String name : metadata.keySet()) {
            if (name.equalsIgnoreCase(column)) {
                return metadata.get(name).placeInOrder;
            }
        }
        return -1;
    }

    @TestVisible
    private static String valueAt(List<Object> row, Integer at) {
        if (at == null || at < 0 || at >= row.size() || row[at] == null) {
            return null;
        }
        return String.valueOf(row[at]);
    }

    /** The query service returns "2026-07-28 08:49:19.151 UTC". */
    @TestVisible
    private static Datetime parseTimestamp(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        try {
            String cleaned = value.trim().removeEnd(' UTC').replace('T', ' ').removeEnd('Z');
            if (cleaned.contains('.')) {
                cleaned = cleaned.substringBefore('.');
            }
            return Datetime.valueOfGmt(cleaned);
        } catch (Exception e) {
            return null;
        }
    }

    private static final Map<String, String> DAY_NAMES = new Map<String, String>{
        'SUN' => 'Sun',
        'MON' => 'Mon',
        'TUE' => 'Tue',
        'WED' => 'Wed',
        'THU' => 'Thu',
        'FRI' => 'Fri',
        'SAT' => 'Sat'
    };

    /**
     * The publish schedule as the segment's own properties dialog states it: "Weekly on Mon",
     * "Every 2 days", "Monthly on day 5".
     *
     * PublishScheduleInterval alone is the hour count and reads as a bare "24", which says
     * nothing about weekly or monthly cadence. The detail is in PublishScheduleInfo, a JSON
     * document, and the interval is only the fallback when no schedule is set at all.
     */
    @TestVisible
    private static String scheduleLabel(String scheduleInfo, String interval) {
        Map<String, Object> info;
        if (String.isNotBlank(scheduleInfo)) {
            try {
                info = (Map<String, Object>) JSON.deserializeUntyped(scheduleInfo);
            } catch (Exception e) {
                info = null;
            }
        }
        if (info == null) {
            return 'NO_REFRESH'.equalsIgnoreCase(interval) ? 'No refresh' : prettify(interval);
        }

        String frequency = String.valueOf(info.get('scheduleFrequency'));
        Integer every = asInteger(info.get('frequency'), 1);
        Integer hours = asInteger(info.get('hourlyInterval'), 24);

        if ('HOURLY'.equalsIgnoreCase(frequency) || (hours > 0 && hours < 24)) {
            return hours == 1 ? 'Hourly' : 'Every ' + hours + ' hours';
        }
        if ('DAILY'.equalsIgnoreCase(frequency)) {
            return every <= 1 ? 'Daily' : 'Every ' + every + ' days';
        }
        if ('WEEKLY'.equalsIgnoreCase(frequency)) {
            String base = every <= 1 ? 'Weekly' : 'Every ' + every + ' weeks';
            String days = dayList(info.get('scheduledDays'));
            return days == null ? base : base + ' on ' + days;
        }
        if ('MONTHLY'.equalsIgnoreCase(frequency)) {
            String base = every <= 1 ? 'Monthly' : 'Every ' + every + ' months';
            Map<String, Object> monthly = (Map<String, Object>) info.get('monthlyInfo');
            if (monthly != null) {
                if (monthly.get('isLastDay') == true) {
                    return base + ' on the last day';
                }
                Integer dayOfMonth = asInteger(monthly.get('dayOfMonth'), 0);
                if (dayOfMonth > 0) {
                    return base + ' on day ' + dayOfMonth;
                }
            }
            return base;
        }

        return String.isBlank(frequency) || frequency == 'null' ? 'No refresh' : prettify(frequency);
    }

    @TestVisible
    private static String dayList(Object scheduledDays) {
        if (!(scheduledDays instanceof List<Object>)) {
            return null;
        }
        List<String> names = new List<String>();
        for (Object day : (List<Object>) scheduledDays) {
            String code = String.valueOf(day).toUpperCase();
            names.add(DAY_NAMES.containsKey(code) ? DAY_NAMES.get(code) : prettify(code));
        }
        return names.isEmpty() ? null : String.join(names, ', ');
    }

    /** Schedule numbers arrive as either JSON numbers or quoted strings. */
    @TestVisible
    private static Integer asInteger(Object value, Integer fallback) {
        if (value == null) {
            return fallback;
        }
        try {
            return Integer.valueOf(String.valueOf(value));
        } catch (Exception e) {
            return fallback;
        }
    }

    /** ACTIVE -> Active, NO_REFRESH -> No refresh. */
    @TestVisible
    private static String prettify(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        String text = value.trim().replace('_', ' ').toLowerCase();
        return text.substring(0, 1).toUpperCase() + text.substring(1);
    }
}
