/**
 * Data provider for the enhanced Data Cloud Profile Explorer detail page.
 *
 * Every endpoint is cacheable and independently callable so each panel on the page can
 * load in parallel and render as soon as its own data arrives. DMO queries carry real
 * latency, so nothing here fans out sequentially more than it has to, and every query is
 * bounded by an explicit LIMIT.
 *
 * Queries run in system mode: Data Cloud DMO fields are frequently not FLS-mapped for
 * end users, and access is already gated by the Data Cloud permission set required to
 * reach Profile Explorer at all.
 *
 * Calculated Insights (__cio) are deliberately absent here. They are not exposed to Apex
 * SOQL ("entity type does not support query") and do not appear in the global describe,
 * so the page keeps the standard Data Cloud Calculated Insights component for that panel.
 */
public with sharing class UnifiedProfileController {
    private static final Integer MAX_SOURCE_IDS = 500;
    private static final Integer MAX_TIMELINE_ROWS = 200;
    private static final Integer DEFAULT_TIMELINE_ROWS = 25;

    private static final Pattern HEX32 = Pattern.compile('^[0-9a-fA-F]{32}$');
    private static final Pattern SAFE_NAME = Pattern.compile('^[A-Za-z0-9_]+$');

    // ------------------------------------------------------------------
    // DTOs
    // ------------------------------------------------------------------

    public class ProfileHeader {
        @AuraEnabled
        public String unifiedId;
        @AuraEnabled
        public String firstName;
        @AuraEnabled
        public String lastName;
        @AuraEnabled
        public String personName;
        @AuraEnabled
        public Datetime lastModified;
        /** Ruleset that produced this profile, and when it last finished building. */
        @AuraEnabled
        public String resolutionName;
        @AuraEnabled
        public Datetime resolutionLastRun;
        @AuraEnabled
        public String resolutionRunStatus;
        @AuraEnabled
        public String email;
        @AuraEnabled
        public String phone;
        @AuraEnabled
        public String addressLine1;
        @AuraEnabled
        public String city;
        @AuraEnabled
        public String stateProvince;
        @AuraEnabled
        public String postalCode;
        @AuraEnabled
        public String country;
        @AuraEnabled
        public String rulesetDmo;
    }

    public class SourceRow {
        @AuraEnabled
        public String sourceRecordId;
        @AuraEnabled
        public String dataSource;
        @AuraEnabled
        public Datetime createdDate;
        @AuraEnabled
        public String value;
        /** Exactly one row per section: the record the unified value is attributed to. */
        @AuraEnabled
        public Boolean isWinner = false;
        /** Carries the same value as the winner without being the attributed record. */
        @AuraEnabled
        public Boolean matchesWinner = false;
        /** Unified contact point this row rolled into. A profile can hold more than one. */
        @AuraEnabled
        public String unifiedRecordId;
    }

    public class BreakdownSection {
        @AuraEnabled
        public String label;
        @AuraEnabled
        public String winnerValue;
        /** Zero rather than null, so an early return still renders a count in the UI. */
        @AuraEnabled
        public Integer totalCount = 0;
        @AuraEnabled
        public List<SourceRow> rows = new List<SourceRow>();

        // Evidence for why the winner value survived reconciliation.
        @AuraEnabled
        public Integer winnerMatchCount = 0;
        @AuraEnabled
        public List<String> winnerSources = new List<String>();
        @AuraEnabled
        public Datetime winnerLatestDate;
        @AuraEnabled
        public Datetime winnerEarliestDate;
        /** How the single winning row was picked out of the rows carrying the winning value. */
        @AuraEnabled
        public String winnerBasis;
        /** Distinct unified values on the profile, of which the winner is the primary one. */
        @AuraEnabled
        public Integer unifiedValueCount = 0;
    }

    public class TimelineEvent implements Comparable {
        @AuraEnabled
        public String id;
        @AuraEnabled
        public String channel;
        @AuraEnabled
        public String eventType;
        @AuraEnabled
        public Datetime eventDateTime;
        @AuraEnabled
        public String campaignName;
        @AuraEnabled
        public String detail;
        @AuraEnabled
        public String sourceIndividualId;
        @AuraEnabled
        public String iconName;

        // Newest first.
        public Integer compareTo(Object other) {
            TimelineEvent that = (TimelineEvent) other;
            if (this.eventDateTime == that.eventDateTime) {
                return 0;
            }
            if (this.eventDateTime == null) {
                return 1;
            }
            if (that.eventDateTime == null) {
                return -1;
            }
            return this.eventDateTime > that.eventDateTime ? -1 : 1;
        }
    }

    public class OrderRow implements Comparable {
        @AuraEnabled
        public String orderNumber;
        @AuraEnabled
        public Date orderDate;
        @AuraEnabled
        public String status;
        @AuraEnabled
        public String channel;
        @AuraEnabled
        public String currencyCode;
        @AuraEnabled
        public Decimal totalAmount;
        @AuraEnabled
        public String customerId;

        /**
         * Newest first, undated last. Sorted on the date the row actually displays, which can
         * come from any of several columns, so the order on screen matches what is shown.
         */
        public Integer compareTo(Object other) {
            Date theirs = ((OrderRow) other).orderDate;
            if (orderDate == theirs) {
                return 0;
            }
            if (orderDate == null) {
                return 1;
            }
            if (theirs == null) {
                return -1;
            }
            return theirs > orderDate ? 1 : -1;
        }
    }

    // ------------------------------------------------------------------
    // Endpoints
    // ------------------------------------------------------------------

    @AuraEnabled(cacheable=true)
    public static ProfileHeader getProfileHeader(String recordId, String objectApiName) {
        UnifiedProfileRegistry.DmoSet dmo = UnifiedProfileRegistry.resolve(objectApiName);
        String unifiedId = resolveUnifiedId(recordId, dmo.unifiedIndividual);

        ProfileHeader header = new ProfileHeader();
        header.unifiedId = unifiedId;
        header.rulesetDmo = dmo.unifiedIndividual;
        applyResolutionRun(header, dmo.rulesetSuffix);
        if (String.isBlank(unifiedId)) {
            return header;
        }

        for (Map<String, Object> row : mapped(safeQuery(
            'SELECT ssot__Id__c, ssot__FirstName__c, ssot__LastName__c, ssot__PersonName__c,' +
                ' ssot__LastModifiedDate__c FROM ' +
                safeName(dmo.unifiedIndividual) +
                ' WHERE ssot__Id__c = :uid LIMIT 1',
            new Map<String, Object>{ 'uid' => unifiedId }
        ))) {
            applyIdentity(header, row);
        }

        Map<String, Object> email = winnerContactPoint(
            dmo.unifiedEmail,
            dmo.emailLink,
            unifiedId,
            'ssot__EmailAddress__c',
            'email'
        );
        if (email != null) {
            header.email = str(email, 'ssot__EmailAddress__c');
        }

        Map<String, Object> phone = winnerContactPoint(
            dmo.unifiedPhone,
            dmo.phoneLink,
            unifiedId,
            'ssot__TelephoneNumber__c, ssot__FormattedE164PhoneNumber__c',
            'phone'
        );
        if (phone != null) {
            String formatted = str(phone, 'ssot__FormattedE164PhoneNumber__c');
            header.phone = String.isNotBlank(formatted) ? formatted : str(phone, 'ssot__TelephoneNumber__c');
        }

        Map<String, Object> address = winnerContactPoint(
            dmo.unifiedAddress,
            dmo.addressLink,
            unifiedId,
            'ssot__AddressLine1__c, ssot__CityName__c, ssot__StateProvinceName__c,' +
                ' ssot__PostalCodeText__c, ssot__CountryName__c',
            'address'
        );
        if (address != null) {
            header.addressLine1 = str(address, 'ssot__AddressLine1__c');
            header.city = str(address, 'ssot__CityName__c');
            header.stateProvince = str(address, 'ssot__StateProvinceName__c');
            header.postalCode = str(address, 'ssot__PostalCodeText__c');
            header.country = str(address, 'ssot__CountryName__c');
        }

        return header;
    }

    @TestVisible
    private static void applyIdentity(ProfileHeader header, Map<String, Object> row) {
        header.firstName = str(row, 'ssot__FirstName__c');
        header.lastName = str(row, 'ssot__LastName__c');
        header.personName = str(row, 'ssot__PersonName__c');
        header.lastModified = (Datetime) row.get('ssot__LastModifiedDate__c');
    }

    /**
     * The contact point the header tile leads with: the same one the breakdown section badges as
     * the winner. Both go through primaryUnifiedId, so the tile and the badge cannot disagree.
     *
     * @param selectList Columns the tile reads, a superset of the ones the value is rendered from
     * @param type email, phone or address
     */
    private static Map<String, Object> winnerContactPoint(
        String unifiedDmo,
        String linkDmo,
        String unifiedId,
        String selectList,
        String type
    ) {
        List<Map<String, Object>> rows = mapped(
            safeQuery(
                'SELECT ssot__Id__c, ' +
                    selectList +
                    ' FROM ' +
                    safeName(unifiedDmo) +
                    ' WHERE ssot__PartyId__c = :uid LIMIT ' +
                    MAX_SOURCE_IDS,
                new Map<String, Object>{ 'uid' => unifiedId }
            )
        );
        if (rows.isEmpty()) {
            return null;
        }

        // The attributed contact point carries the profile's own id, and when it holds a value
        // it wins outright, so the contributor counts need not be read at all.
        Map<String, Object> attributed = attributedContactPoint(rows, unifiedId, type);
        if (attributed != null) {
            return attributed;
        }

        return pickContactPoint(rows, unifiedLinkCounts(linkDmo, idsOf(rows)), unifiedId, type);
    }

    /** The unified contact point keyed by the profile's own id, when it holds a value. */
    @TestVisible
    private static Map<String, Object> attributedContactPoint(
        List<Map<String, Object>> rows,
        String unifiedId,
        String type
    ) {
        for (Map<String, Object> row : rows) {
            if (unifiedId != null && unifiedId.equals(str(row, 'ssot__Id__c'))) {
                return String.isBlank(renderContactPoint(row, type)) ? null : row;
            }
        }
        return null;
    }

    /** The unified contact point the section leads with, out of the several a profile can hold. */
    @TestVisible
    private static Map<String, Object> pickContactPoint(
        List<Map<String, Object>> rows,
        Map<String, Integer> counts,
        String unifiedId,
        String type
    ) {
        Map<String, Map<String, Object>> rowsById = new Map<String, Map<String, Object>>();
        Map<String, String> values = new Map<String, String>();
        for (Map<String, Object> row : rows) {
            String cpId = str(row, 'ssot__Id__c');
            if (String.isNotBlank(cpId)) {
                rowsById.put(cpId, row);
                values.put(cpId, renderContactPoint(row, type));
            }
        }
        return rowsById.get(primaryUnifiedId(values, counts, unifiedId));
    }

    @TestVisible
    private static List<String> idsOf(List<Map<String, Object>> rows) {
        Set<String> ids = new Set<String>();
        for (Map<String, Object> row : rows) {
            String id = str(row, 'ssot__Id__c');
            if (String.isNotBlank(id)) {
                ids.add(id);
            }
        }
        return new List<String>(ids);
    }

    /** Contributing source records behind each unified contact point, counted once per record. */
    private static Map<String, Integer> unifiedLinkCounts(String linkDmo, List<String> unifiedCpIds) {
        return countLinks(
            mapped(
                safeQuery(
                    'SELECT SourceRecordId__c, UnifiedRecordId__c FROM ' +
                        safeName(linkDmo) +
                        ' WHERE UnifiedRecordId__c IN :ids LIMIT ' +
                        MAX_SOURCE_IDS,
                    new Map<String, Object>{ 'ids' => unifiedCpIds }
                )
            )
        );
    }

    @TestVisible
    private static Map<String, Integer> countLinks(List<Map<String, Object>> links) {
        Map<String, Integer> counts = new Map<String, Integer>();
        Set<String> pairs = new Set<String>();

        for (Map<String, Object> link : links) {
            String sourceId = str(link, 'SourceRecordId__c');
            String unifiedCpId = str(link, 'UnifiedRecordId__c');
            if (String.isBlank(sourceId) || !pairs.add(sourceId + '|' + unifiedCpId)) {
                continue;
            }
            Integer count = counts.get(unifiedCpId);
            counts.put(unifiedCpId, count == null ? 1 : count + 1);
        }
        return counts;
    }

    /** Contributing source individuals behind the unified record. */
    @AuraEnabled(cacheable=true)
    public static BreakdownSection getIndividualBreakdown(String recordId, String objectApiName) {
        UnifiedProfileRegistry.DmoSet dmo = UnifiedProfileRegistry.resolve(objectApiName);
        String unifiedId = resolveUnifiedId(recordId, dmo.unifiedIndividual);

        BreakdownSection section = new BreakdownSection();
        section.label = 'Individuals';
        if (String.isBlank(unifiedId)) {
            return section;
        }

        Map<String, SourceRow> byId = contributingIndividuals(
            mapped(
                safeQuery(
                    'SELECT SourceRecordId__c, ssot__DataSourceId__c, CreatedDate__c FROM ' +
                        safeName(dmo.individualLink) +
                        ' WHERE UnifiedRecordId__c = :uid LIMIT ' +
                        MAX_SOURCE_IDS,
                    new Map<String, Object>{ 'uid' => unifiedId }
                )
            )
        );

        if (!byId.isEmpty()) {
            List<String> ids = new List<String>(byId.keySet());
            applyIndividualNames(
                byId,
                mapped(
                    safeQuery(
                        'SELECT ssot__Id__c, ssot__FirstName__c, ssot__LastName__c, ssot__PersonName__c FROM ' +
                            safeName(UnifiedProfileRegistry.SRC_INDIVIDUAL) +
                            ' WHERE ssot__Id__c IN :ids LIMIT ' +
                            MAX_SOURCE_IDS,
                        new Map<String, Object>{ 'ids' => ids }
                    )
                )
            );
        }

        /*
         * The unified record carries the reconciled name and, on most rulesets, the source record
         * id that reconciliation attributed it to. That id names the winning row outright, which
         * matters when several contributing records share the same name.
         */
        String reconciledName;
        String attributedId;
        String nameFields = 'ssot__PersonName__c, ssot__FirstName__c, ssot__LastName__c';
        Map<String, Object> uidBind = new Map<String, Object>{ 'uid' => unifiedId };
        String tail = ' FROM ' + safeName(dmo.unifiedIndividual) + ' WHERE ssot__Id__c = :uid LIMIT 1';

        List<SObject> unifiedRows = safeQuery('SELECT ssot__ExternalRecordId__c, ' + nameFields + tail, uidBind);
        Boolean hasAttribution = !unifiedRows.isEmpty();
        if (!hasAttribution) {
            // Older rulesets do not expose the attribution column; the name alone still identifies
            // the winning value, and the row is then picked on recency.
            unifiedRows = safeQuery('SELECT ' + nameFields + tail, uidBind);
        }

        for (Map<String, Object> row : mapped(unifiedRows)) {
            reconciledName = personName(row);
            if (hasAttribution) {
                attributedId = str(row, 'ssot__ExternalRecordId__c');
            }
        }

        section.rows = byId.values();
        section.totalCount = section.rows.size();
        applyWinnerEvidence(section, reconciledName, attributedId);

        // The badge carries the winning individual's id; the name is already on the header.
        for (SourceRow r : section.rows) {
            if (r.isWinner) {
                section.winnerValue = r.sourceRecordId;
                break;
            }
        }
        return section;
    }

    /** One row per contributing individual, folding in the link rows a rerun has rewritten. */
    @TestVisible
    private static Map<String, SourceRow> contributingIndividuals(List<Map<String, Object>> links) {
        Map<String, SourceRow> byId = new Map<String, SourceRow>();
        for (Map<String, Object> link : links) {
            SourceRow r = linkRow(link);
            if (String.isNotBlank(r.sourceRecordId)) {
                mergeLink(byId, r.sourceRecordId, r);
            }
        }
        return byId;
    }

    @TestVisible
    private static void applyIndividualNames(Map<String, SourceRow> byId, List<Map<String, Object>> individuals) {
        for (Map<String, Object> ind : individuals) {
            SourceRow r = byId.get(str(ind, 'ssot__Id__c'));
            if (r != null) {
                r.value = personName(ind);
            }
        }
    }

    private static SourceRow linkRow(Map<String, Object> link) {
        SourceRow r = new SourceRow();
        r.sourceRecordId = str(link, 'SourceRecordId__c');
        r.unifiedRecordId = str(link, 'UnifiedRecordId__c');
        r.dataSource = str(link, 'ssot__DataSourceId__c');
        r.createdDate = (Datetime) link.get('CreatedDate__c');
        return r;
    }

    private static String personName(Map<String, Object> row) {
        return displayName(
            str(row, 'ssot__PersonName__c'),
            str(row, 'ssot__FirstName__c'),
            str(row, 'ssot__LastName__c')
        );
    }

    /**
     * @param cpType Email, Phone or Address
     */
    @AuraEnabled(cacheable=true)
    public static BreakdownSection getContactPointBreakdown(String recordId, String objectApiName, String cpType) {
        UnifiedProfileRegistry.DmoSet dmo = UnifiedProfileRegistry.resolve(objectApiName);
        String unifiedId = resolveUnifiedId(recordId, dmo.unifiedIndividual);

        String type = String.isBlank(cpType) ? 'Email' : cpType.trim().toLowerCase();
        BreakdownSection section = new BreakdownSection();

        String unifiedDmo;
        String linkDmo;
        String sourceDmo;
        String valueSelect;
        if (type == 'phone') {
            section.label = 'Phone Numbers';
            unifiedDmo = dmo.unifiedPhone;
            linkDmo = dmo.phoneLink;
            sourceDmo = UnifiedProfileRegistry.SRC_PHONE;
            valueSelect = 'ssot__TelephoneNumber__c';
        } else if (type == 'address') {
            section.label = 'Addresses';
            unifiedDmo = dmo.unifiedAddress;
            linkDmo = dmo.addressLink;
            sourceDmo = UnifiedProfileRegistry.SRC_ADDRESS;
            valueSelect = 'ssot__AddressLine1__c, ssot__CityName__c, ssot__StateProvinceName__c, ssot__PostalCodeText__c';
        } else {
            section.label = 'Emails';
            unifiedDmo = dmo.unifiedEmail;
            linkDmo = dmo.emailLink;
            sourceDmo = UnifiedProfileRegistry.SRC_EMAIL;
            valueSelect = 'ssot__EmailAddress__c';
        }

        if (String.isBlank(unifiedId)) {
            return section;
        }

        /*
         * A profile can hold several unified contact points of one type - two email addresses,
         * say - each reconciled separately with its own contributors. They are all read, and the
         * badge then reports the primary one.
         */
        Map<String, String> unifiedValues = unifiedContactValues(
            mapped(
                safeQuery(
                    'SELECT ssot__Id__c, ' +
                        valueSelect +
                        ' FROM ' +
                        safeName(unifiedDmo) +
                        ' WHERE ssot__PartyId__c = :uid LIMIT ' +
                        MAX_SOURCE_IDS,
                    new Map<String, Object>{ 'uid' => unifiedId }
                )
            ),
            type
        );

        section.unifiedValueCount = unifiedValues.size();
        if (unifiedValues.isEmpty()) {
            return section;
        }

        List<String> unifiedCpIds = new List<String>(unifiedValues.keySet());
        List<Map<String, Object>> links = mapped(
            safeQuery(
                'SELECT SourceRecordId__c, UnifiedRecordId__c, ssot__DataSourceId__c, CreatedDate__c FROM ' +
                    safeName(linkDmo) +
                    ' WHERE UnifiedRecordId__c IN :ids LIMIT ' +
                    MAX_SOURCE_IDS,
                new Map<String, Object>{ 'ids' => unifiedCpIds }
            )
        );

        // Source ids repeat when one record supplied several values, so every value is kept and
        // matched back to the unified value the link points at.
        List<String> srcIds = contributingSourceIds(links);
        Map<String, List<String>> sourceValues = new Map<String, List<String>>();
        if (!srcIds.isEmpty()) {
            sourceValues = sourceContactValues(
                mapped(
                    safeQuery(
                        'SELECT ssot__Id__c, ' +
                            valueSelect +
                            ' FROM ' +
                            safeName(sourceDmo) +
                            ' WHERE ssot__Id__c IN :ids LIMIT ' +
                            MAX_SOURCE_IDS,
                        new Map<String, Object>{ 'ids' => srcIds }
                    )
                ),
                type
            );
        }

        fillContactSection(
            section,
            unifiedValues,
            links,
            sourceValues,
            unifiedId,
            attributedSourceId(dmo.unifiedIndividual, unifiedId)
        );
        return section;
    }

    @TestVisible
    private static Map<String, String> unifiedContactValues(List<Map<String, Object>> rows, String type) {
        Map<String, String> values = new Map<String, String>();
        for (Map<String, Object> cp : rows) {
            String cpId = str(cp, 'ssot__Id__c');
            if (String.isNotBlank(cpId)) {
                values.put(cpId, renderContactPoint(cp, type));
            }
        }
        return values;
    }

    @TestVisible
    private static Map<String, List<String>> sourceContactValues(List<Map<String, Object>> rows, String type) {
        Map<String, List<String>> values = new Map<String, List<String>>();
        for (Map<String, Object> cp : rows) {
            String id = str(cp, 'ssot__Id__c');
            if (!values.containsKey(id)) {
                values.put(id, new List<String>());
            }
            values.get(id).add(renderContactPoint(cp, type));
        }
        return values;
    }

    @TestVisible
    private static List<String> contributingSourceIds(List<Map<String, Object>> links) {
        Set<String> ids = new Set<String>();
        for (Map<String, Object> link : links) {
            String id = str(link, 'SourceRecordId__c');
            if (String.isNotBlank(id)) {
                ids.add(id);
            }
        }
        return new List<String>(ids);
    }

    /**
     * Turns the three reads into the section the page renders: one row per link rather than per
     * source record, since a record that supplied two different values contributed to each of
     * them separately, and then the winner among them.
     */
    @TestVisible
    private static void fillContactSection(
        BreakdownSection section,
        Map<String, String> unifiedValues,
        List<Map<String, Object>> links,
        Map<String, List<String>> sourceValues,
        String unifiedId,
        String attributedId
    ) {
        List<SourceRow> rows = new List<SourceRow>();
        Map<String, Integer> linkCounts = new Map<String, Integer>();
        Map<String, SourceRow> byPair = new Map<String, SourceRow>();

        for (Map<String, Object> link : links) {
            SourceRow r = linkRow(link);
            if (String.isBlank(r.sourceRecordId)) {
                continue;
            }
            if (!mergeLink(byPair, r.sourceRecordId + '|' + r.unifiedRecordId, r)) {
                continue;
            }

            rows.add(r);
            Integer count = linkCounts.get(r.unifiedRecordId);
            linkCounts.put(r.unifiedRecordId, count == null ? 1 : count + 1);
        }

        for (SourceRow r : rows) {
            r.value = pickSourceValue(sourceValues.get(r.sourceRecordId), unifiedValues.get(r.unifiedRecordId));
        }

        section.rows = rows;
        section.totalCount = rows.size();

        String primaryCpId = primaryUnifiedId(unifiedValues, linkCounts, unifiedId);
        section.winnerValue = unifiedValues.get(primaryCpId);
        applyWinnerEvidence(section, section.winnerValue, attributedId, primaryCpId);
    }

    /**
     * Records one contribution, folding in a link row the ruleset has written before.
     *
     * Identity resolution writes a fresh link row each time it rebuilds a match it already knew
     * about, so the same contribution arrives several times with different dates. The date that
     * means something is the earliest: when the record joined the profile, rather than when the
     * ruleset last ran.
     *
     * @return true when this is a contribution not seen before
     */
    @TestVisible
    private static Boolean mergeLink(Map<String, SourceRow> byKey, String key, SourceRow candidate) {
        SourceRow existing = byKey.get(key);
        if (existing == null) {
            byKey.put(key, candidate);
            return true;
        }

        if (
            existing.createdDate == null ||
            (candidate.createdDate != null && candidate.createdDate < existing.createdDate)
        ) {
            existing.createdDate = candidate.createdDate;
        }
        return false;
    }

    /**
     * When the ruleset behind this profile last finished building.
     *
     * The unified record's own last modified date only says when that row was last rewritten,
     * which on a profile the latest run left untouched reads as a date weeks in the past. The
     * ruleset is matched on the suffix its DMO names carry, and the query is dynamic so an org
     * without the object, or a user without access to it, simply gets no run date.
     */
    private static void applyResolutionRun(ProfileHeader header, String suffix) {
        String predicate = String.isBlank(suffix)
            ? 'Suffix = null OR Suffix = \'\''
            : 'Suffix = :suffix';

        try {
            for (SObject r : Database.queryWithBinds(
                'SELECT Name, LastRunStatus, LastRunStatusDateTime, LastSuccessfulRunDateTime' +
                    ' FROM IdentityResolution WHERE ' +
                    predicate +
                    ' ORDER BY LastSuccessfulRunDateTime DESC NULLS LAST LIMIT 1',
                new Map<String, Object>{ 'suffix' => suffix },
                AccessLevel.USER_MODE
            )) {
                header.resolutionName = str(r, 'Name');
                header.resolutionRunStatus = str(r, 'LastRunStatus');
                Datetime succeeded = (Datetime) r.get('LastSuccessfulRunDateTime');
                header.resolutionLastRun = succeeded == null
                    ? (Datetime) r.get('LastRunStatusDateTime')
                    : succeeded;
            }
        } catch (Exception e) {
            // Header still renders; the UI falls back to the unified record's own date.
        }
    }

    /** The value the link points at, so a record that supplied two is read the right way round. */
    @TestVisible
    private static String pickSourceValue(List<String> candidates, String unifiedValue) {
        if (candidates == null || candidates.isEmpty()) {
            return null;
        }
        if (String.isNotBlank(unifiedValue)) {
            for (String c : candidates) {
                if (unifiedValue.equalsIgnoreCase(c)) {
                    return c;
                }
            }
        }
        return candidates[0];
    }

    /**
     * The unified contact point the section leads with. Data Cloud keys the contact point that
     * came from the attributed source record with the profile's own unified id, so that one is
     * the primary; failing that, the value the most source records agreed on. A unified record
     * with nothing mapped is passed over, which is what keeps the badge and the header tile
     * showing the same value.
     */
    @TestVisible
    private static String primaryUnifiedId(
        Map<String, String> unifiedValues,
        Map<String, Integer> linkCounts,
        String unifiedId
    ) {
        if (String.isNotBlank(unifiedValues.get(unifiedId))) {
            return unifiedId;
        }

        String best;
        Integer bestCount = -1;
        for (String cpId : unifiedValues.keySet()) {
            if (String.isBlank(unifiedValues.get(cpId))) {
                continue;
            }
            Integer count = linkCounts.containsKey(cpId) ? linkCounts.get(cpId) : 0;
            if (count > bestCount || (count == bestCount && cpId.compareTo(best) < 0)) {
                best = cpId;
                bestCount = count;
            }
        }
        // Every unified value is empty, so the primary stands even though it renders as nothing.
        return best == null ? unifiedId : best;
    }

    @AuraEnabled(cacheable=true)
    public static List<TimelineEvent> getEngagementTimeline(String recordId, String objectApiName, Integer maxRows) {
        UnifiedProfileRegistry.DmoSet dmo = UnifiedProfileRegistry.resolve(objectApiName);
        String unifiedId = resolveUnifiedId(recordId, dmo.unifiedIndividual);
        Integer cap = boundRows(maxRows);

        List<TimelineEvent> events = new List<TimelineEvent>();
        List<String> srcIds = sourceRecordIds(unifiedId, dmo.individualLink);
        if (srcIds.isEmpty()) {
            return events;
        }

        Set<String> bulkMessageIds = new Set<String>();
        Set<String> seen = new Set<String>();

        String emailSelect =
            'SELECT ssot__Id__c, ssot__IndividualId__c, ssot__EngagementDateTm__c,' +
            ' ssot__EngagementChannelActionId__c, ssot__EngagementTypeId__c,' +
            ' ssot__BulkEmailMessageId__c, ssot__EmailName__c, ssot__LinkName__c FROM ' +
            safeName(UnifiedProfileRegistry.EMAIL_ENGAGEMENT);
        String emailTail = ' ORDER BY ssot__EngagementDateTm__c DESC LIMIT ' + cap;

        for (Map<String, Object> e : mapped(
            safeQuery(
                emailSelect + ' WHERE ssot__IndividualId__c IN :ids' + emailTail,
                new Map<String, Object>{ 'ids' => srcIds }
            )
        )) {
            addEmailEvent(events, seen, bulkMessageIds, e);
        }

        /*
         * Engagement that arrives without an individual, as file loads usually do, names the
         * person by the address it was sent to. Every address on the profile counts, not just
         * the winning one, so a record is not dropped for holding a runner-up address.
         */
        List<String> addresses = profileEmailAddresses(unifiedId, srcIds);
        if (!addresses.isEmpty()) {
            for (Map<String, Object> e : mapped(
                safeQuery(
                    emailSelect + ' WHERE ssot__SendtimeEmailAddress__c IN :addresses' + emailTail,
                    new Map<String, Object>{ 'addresses' => addresses }
                )
            )) {
                addEmailEvent(events, seen, bulkMessageIds, e);
            }
        }

        Map<String, Object> webBinds = new Map<String, Object>{ 'ids' => srcIds };
        List<SObject> webRows = queryOrNull(webEngagementSoql(true, cap), webBinds);
        if (webRows == null) {
            // The status column is not mapped in this org, and an unmapped column takes the
            // whole query down with it.
            webRows = safeQuery(webEngagementSoql(false, cap), webBinds);
        }

        for (Map<String, Object> w : mapped(webRows)) {
            events.add(webEvent(w));
        }

        resolveCampaignNames(events, bulkMessageIds);

        events.sort();
        return trimTo(events, cap);
    }

    @TestVisible
    private static TimelineEvent webEvent(Map<String, Object> w) {
        TimelineEvent ev = new TimelineEvent();
        ev.id = str(w, 'ssot__Id__c');
        ev.channel = 'Web';
        ev.sourceIndividualId = str(w, 'ssot__IndividualId__c');
        ev.eventDateTime = (Datetime) w.get('ssot__EngagementDateTm__c');
        ev.eventType = friendlyAction(webAction(w), 'Web');
        ev.iconName = 'utility:world';
        ev.campaignName = str(w, 'ssot__UtmCampaignName__c');
        String title = str(w, 'ssot__PagePublicTitleName__c');
        ev.detail = String.isNotBlank(title) ? title : str(w, 'ssot__PageURL__c');
        return ev;
    }

    @TestVisible
    private static List<TimelineEvent> trimTo(List<TimelineEvent> events, Integer cap) {
        if (events.size() <= cap) {
            return events;
        }
        List<TimelineEvent> trimmed = new List<TimelineEvent>();
        for (Integer i = 0; i < cap; i++) {
            trimmed.add(events[i]);
        }
        return trimmed;
    }

    /**
     * Orders for every contributing individual, newest first, read from the standard Sales
     * Order DMO.
     *
     * Not cacheable: the Sales Order DMO is only reachable through the Data Cloud query
     * service, which is a callout. Plain SOQL against it fails with an uncatchable error.
     */
    @AuraEnabled
    public static List<OrderRow> getOrderTimeline(String recordId, String objectApiName, Integer maxRows) {
        UnifiedProfileRegistry.DmoSet dmo = UnifiedProfileRegistry.resolve(objectApiName);
        String unifiedId = resolveUnifiedId(recordId, dmo.unifiedIndividual);
        Integer cap = boundRows(maxRows);

        List<OrderRow> orders = new List<OrderRow>();
        List<String> srcIds = sourceRecordIds(unifiedId, dmo.individualLink);
        if (srcIds.isEmpty()) {
            return orders;
        }

        // Every column the DMO documents for this panel. Whichever ones this org has not
        // mapped are dropped by the query helper, so a partial mapping still renders.
        List<String> columns = new List<String>{
            SO_ID,
            SO_NUMBER,
            SO_SOLD_TO,
            SO_BILL_TO,
            SO_GRAND_TOTAL,
            SO_PRODUCT_TOTAL,
            SO_TAX_TOTAL,
            SO_CURRENCY,
            SO_START_DATE,
            SO_CREATED,
            SO_PRICE_DATE,
            SO_CHANNEL,
            SO_STATUS
        };

        String ids = quotedList(srcIds);
        String predicate = '(' + SO_SOLD_TO + ' IN (' + ids + ') OR ' + SO_BILL_TO + ' IN (' + ids + '))';

        CdpRows result = queryDroppingUnknownColumns(
            columns,
            'FROM ' + UnifiedProfileRegistry.SALES_ORDER + ' WHERE ' + predicate,
            SO_START_DATE,
            cap
        );

        orders = orderRows(result);
        orders.sort();
        return orders;
    }

    @TestVisible
    private static List<OrderRow> orderRows(CdpRows result) {
        List<OrderRow> orders = new List<OrderRow>();
        for (List<Object> row : result.rows) {
            OrderRow o = new OrderRow();
            o.orderNumber = firstText(result, row, new List<String>{ SO_NUMBER, SO_ID });
            o.customerId = firstText(result, row, new List<String>{ SO_SOLD_TO, SO_BILL_TO });
            o.status = result.text(row, SO_STATUS);
            o.channel = result.text(row, SO_CHANNEL);
            o.currencyCode = result.text(row, SO_CURRENCY);
            o.orderDate = firstDate(result, row, new List<String>{ SO_START_DATE, SO_CREATED, SO_PRICE_DATE });
            o.totalAmount = orderValue(result, row);
            orders.add(o);
        }
        return orders;
    }

    /**
     * The documented grand total when the org maps it, otherwise product plus tax, which is
     * what the remaining documented components add up to. Null when nothing is mapped, so the
     * UI can distinguish an unmapped amount from a genuine zero.
     */
    @TestVisible
    private static Decimal orderValue(CdpRows result, List<Object> row) {
        Decimal grand = result.number(row, SO_GRAND_TOTAL);
        if (grand != null) {
            return grand.setScale(2);
        }

        Decimal product = result.number(row, SO_PRODUCT_TOTAL);
        Decimal tax = result.number(row, SO_TAX_TOTAL);
        if (product == null && tax == null) {
            return null;
        }
        return ((product == null ? 0 : product) + (tax == null ? 0 : tax)).setScale(2);
    }

    @TestVisible
    private static String firstText(CdpRows result, List<Object> row, List<String> columns) {
        for (String c : columns) {
            String value = result.text(row, c);
            if (String.isNotBlank(value)) {
                return value;
            }
        }
        return null;
    }

    @TestVisible
    private static Date firstDate(CdpRows result, List<Object> row, List<String> columns) {
        for (String c : columns) {
            Date value = result.dateOf(row, c);
            if (value != null) {
                return value;
            }
        }
        return null;
    }

    // ------------------------------------------------------------------
    // Internals
    // ------------------------------------------------------------------

    // ------------------------------------------------------------------
    // Sales Order, read through the Data Cloud query service
    // ------------------------------------------------------------------

    private static final String SO_ID = 'ssot__Id__c';
    private static final String SO_NUMBER = 'ssot__OrderNumber__c';
    private static final String SO_SOLD_TO = 'ssot__SoldToCustomerId__c';
    private static final String SO_BILL_TO = 'ssot__BillToContactId__c';
    private static final String SO_GRAND_TOTAL = 'ssot__GrandTotalAmount__c';
    private static final String SO_PRODUCT_TOTAL = 'ssot__TotalProductAmount__c';
    private static final String SO_TAX_TOTAL = 'ssot__TotalTaxAmount__c';
    private static final String SO_CURRENCY = 'ssot__CurrencyCode__c';
    private static final String SO_START_DATE = 'ssot__OrderStartDate__c';
    private static final String SO_CREATED = 'ssot__CreatedDate__c';
    private static final String SO_PRICE_DATE = 'ssot__PriceDate__c';
    private static final String SO_CHANNEL = 'ssot__SalesChannelId__c';
    private static final String SO_STATUS = 'ssot__SalesOrderStatusId__c';

    private static final Integer MAX_COLUMN_RETRIES = 8;
    private static final Pattern UNKNOWN_COLUMN = Pattern.compile('unknown column \'([^\']+)\'');

    /** Query service rows, addressed by column name rather than by position. */
    @TestVisible
    private class CdpRows {
        @TestVisible
        Map<String, Integer> index = new Map<String, Integer>();
        @TestVisible
        List<List<Object>> rows = new List<List<Object>>();

        Object raw(List<Object> row, String column) {
            Integer i = index.get(column);
            if (i == null || i >= row.size()) {
                return null;
            }
            return row[i];
        }

        @TestVisible
        String text(List<Object> row, String column) {
            Object value = raw(row, column);
            return value == null ? null : String.valueOf(value);
        }

        @TestVisible
        Decimal number(List<Object> row, String column) {
            String value = text(row, column);
            if (String.isBlank(value)) {
                return null;
            }
            try {
                return Decimal.valueOf(value);
            } catch (Exception e) {
                return null;
            }
        }

        /** Timestamps arrive as "2026-04-21 00:00:00.000 UTC" and only the day is displayed. */
        @TestVisible
        Date dateOf(List<Object> row, String column) {
            String value = text(row, column);
            if (String.isBlank(value) || value.length() < 10) {
                return null;
            }
            try {
                return Date.valueOf(value.substring(0, 10));
            } catch (Exception e) {
                return null;
            }
        }
    }

    /**
     * Runs a query and, when the org has not mapped one of the requested columns, drops it and
     * retries. A single documented field list therefore works across orgs that map different
     * subsets of the DMO, instead of the panel failing outright on the first missing field.
     */
    private static CdpRows queryDroppingUnknownColumns(
        List<String> columns,
        String fromWhere,
        String orderBy,
        Integer rowLimit
    ) {
        CdpRows result = new CdpRows();
        List<String> remaining = new List<String>(columns);

        for (Integer attempt = 0; attempt <= MAX_COLUMN_RETRIES && !remaining.isEmpty(); attempt++) {
            String sql = 'SELECT ' + String.join(remaining, ', ') + ' ' + fromWhere;
            if (remaining.contains(orderBy)) {
                sql += ' ORDER BY ' + orderBy + ' DESC';
            }
            sql += ' LIMIT ' + rowLimit;

            try {
                ConnectApi.CdpQueryInput input = new ConnectApi.CdpQueryInput();
                input.sql = sql;
                ConnectApi.CdpQueryOutputV2 output = ConnectApi.CdpQuery.queryAnsiSqlV2(input);

                if (output.metadata != null) {
                    for (String column : output.metadata.keySet()) {
                        result.index.put(column, output.metadata.get(column).placeInOrder);
                    }
                }
                if (output.data != null) {
                    for (Integer i = 0; i < output.data.size(); i++) {
                        result.rows.add(output.data[i].rowData);
                    }
                }
                return result;
            } catch (Exception e) {
                String missing = unmappedColumn(e.getMessage());
                Integer at = missing == null ? -1 : remaining.indexOf(missing);
                if (at < 0) {
                    // Not a mapping problem. An empty panel beats a broken page.
                    return result;
                }
                remaining.remove(at);
            }
        }
        return result;
    }

    @TestVisible
    private static String unmappedColumn(String message) {
        if (String.isBlank(message)) {
            return null;
        }
        Matcher m = UNKNOWN_COLUMN.matcher(message);
        return m.find() ? m.group(1) : null;
    }

    @TestVisible
    private static String quotedList(List<String> values) {
        List<String> quoted = new List<String>();
        for (String value : values) {
            if (String.isNotBlank(value)) {
                quoted.add('\'' + value.replace('\'', '\'\'') + '\'');
            }
        }
        return quoted.isEmpty() ? '\'\'' : String.join(quoted, ', ');
    }

    /** Shared with UnifiedInsightController so both resolve the profile key identically. */
    public static String resolveUnifiedIdFor(String recordId, String objectApiName) {
        UnifiedProfileRegistry.DmoSet dmo = UnifiedProfileRegistry.resolve(objectApiName);
        return resolveUnifiedId(recordId, dmo.unifiedIndividual);
    }

    @TestVisible
    private static Map<String, String> unifiedIdCache = new Map<String, String>();

    private static String resolveUnifiedId(String recordId, String unifiedDmo) {
        if (String.isBlank(recordId)) {
            return null;
        }
        // Profile Explorer already hands us the 32-char unified key in most cases.
        if (HEX32.matcher(recordId).matches()) {
            return recordId;
        }
        String cacheKey = unifiedDmo + '|' + recordId;
        if (unifiedIdCache.containsKey(cacheKey)) {
            return unifiedIdCache.get(cacheKey);
        }

        // A CDP record page hands over the DMO row id instead. Filtering a Data Cloud object by a
        // malformed id fails inside the query service with an uncatchable exception, so the value
        // is validated here, where a bad id raises an ordinary catchable one.
        Id rowId;
        try {
            rowId = Id.valueOf(recordId);
        } catch (Exception e) {
            unifiedIdCache.put(cacheKey, null);
            return null;
        }

        String resolved = null;
        for (SObject row : safeQuery(
            'SELECT ssot__Id__c FROM ' + safeName(unifiedDmo) + ' WHERE Id = :rid LIMIT 1',
            new Map<String, Object>{ 'rid' => rowId }
        )) {
            resolved = str(row, 'ssot__Id__c');
        }
        unifiedIdCache.put(cacheKey, resolved);
        return resolved;
    }

    /**
     * Every id this profile answers to: its unified id and the ids of the records that built it.
     * A related object can key off either, so a caller filtering another DMO matches on the set.
     */
    public static List<String> profileIdentifiers(String recordId, String objectApiName) {
        UnifiedProfileRegistry.DmoSet dmo = UnifiedProfileRegistry.resolve(objectApiName);
        String unifiedId = resolveUnifiedId(recordId, dmo.unifiedIndividual);
        if (String.isBlank(unifiedId)) {
            return new List<String>();
        }

        Set<String> ids = new Set<String>{ unifiedId };
        ids.addAll(sourceRecordIds(unifiedId, dmo.individualLink));
        return new List<String>(ids);
    }

    @TestVisible
    private static Map<String, String> attributionCache = new Map<String, String>();

    /**
     * Source record id the ruleset attributed the profile to, where the ruleset publishes one.
     * It names the winning row directly, which is what settles a section whose contributing
     * records all carry the same value.
     */
    private static String attributedSourceId(String unifiedDmo, String unifiedId) {
        if (String.isBlank(unifiedId)) {
            return null;
        }
        String key = unifiedDmo + '|' + unifiedId;
        if (attributionCache.containsKey(key)) {
            return attributionCache.get(key);
        }

        String attributed = null;
        for (SObject row : safeQuery(
            'SELECT ssot__ExternalRecordId__c FROM ' +
                safeName(unifiedDmo) +
                ' WHERE ssot__Id__c = :uid LIMIT 1',
            new Map<String, Object>{ 'uid' => unifiedId }
        )) {
            attributed = str(row, 'ssot__ExternalRecordId__c');
        }
        attributionCache.put(key, attributed);
        return attributed;
    }

    @TestVisible
    private static void applyWinnerEvidence(BreakdownSection section, String matchValue, String attributedId) {
        applyWinnerEvidence(section, matchValue, attributedId, null);
    }

    /**
     * Picks the single contributing row the unified value came from, and summarises how that
     * value compares across the other sources.
     *
     * Two steps, because they answer different questions. Which value won is read from the
     * unified record itself. Which row that value is attributed to is the unified record's own
     * source record id where the ruleset publishes one, and otherwise the most recently created
     * of the rows carrying the value, matching the default Most Recent reconciliation rule.
     *
     * The ruleset's configured reconciliation rule is not exposed through any Apex or Metadata
     * surface, so the rest is reported as observable evidence (how many records agree, which
     * systems supplied the value, how recent they are) rather than asserted.
     *
     * @param matchValue      Value compared against each contributing row. Separate from the
     *                        displayed winner because Individuals is matched on the reconciled
     *                        name but badges the winning record's id.
     * @param attributedId    Source record id the unified record names, when it names one.
     * @param unifiedRecordId Restricts the winner to the contributors of one unified value, so a
     *                        second email on the profile cannot claim the first one's row.
     */
    @TestVisible
    private static void applyWinnerEvidence(
        BreakdownSection section,
        String matchValue,
        String attributedId,
        String unifiedRecordId
    ) {
        // Nothing reconciled to compare against, so nothing is flagged. Some rulesets leave a
        // contact point with no mapped value at all.
        if (section.rows.isEmpty() || String.isBlank(matchValue)) {
            return;
        }

        List<SourceRow> inScope = new List<SourceRow>();
        List<SourceRow> carriers = new List<SourceRow>();
        Set<String> sources = new Set<String>();
        Datetime latest;
        Datetime earliest;

        for (SourceRow r : section.rows) {
            r.isWinner = false;
            r.matchesWinner = false;
            if (unifiedRecordId != null && r.unifiedRecordId != unifiedRecordId) {
                continue;
            }
            inScope.add(r);
            if (r.value == null || !r.value.equalsIgnoreCase(matchValue)) {
                continue;
            }
            carriers.add(r);
            if (String.isNotBlank(r.dataSource)) {
                sources.add(r.dataSource);
            }
            if (r.createdDate != null) {
                if (latest == null || r.createdDate > latest) {
                    latest = r.createdDate;
                }
                if (earliest == null || r.createdDate < earliest) {
                    earliest = r.createdDate;
                }
            }
        }

        section.winnerMatchCount = carriers.size();
        section.winnerSources = new List<String>(sources);
        section.winnerLatestDate = latest;
        section.winnerEarliestDate = earliest;

        SourceRow winner = attributedRow(inScope, carriers, attributedId);
        if (winner == null) {
            return;
        }

        for (SourceRow r : carriers) {
            r.matchesWinner = r != winner;
        }
        winner.isWinner = true;
        winner.matchesWinner = false;
        section.winnerBasis = winnerBasis(winner, carriers, attributedId);
    }

    /**
     * Prefers the row the unified record points at. A row named there but not carrying the value
     * still wins, since the ruleset attributed the profile to it either way.
     */
    @TestVisible
    private static SourceRow attributedRow(
        List<SourceRow> allRows,
        List<SourceRow> carriers,
        String attributedId
    ) {
        if (String.isNotBlank(attributedId)) {
            for (SourceRow r : allRows) {
                if (attributedId.equalsIgnoreCase(r.sourceRecordId)) {
                    return r;
                }
            }
        }

        // Most recent, then lowest id, so a redraw never moves the flag between tied rows.
        SourceRow best;
        for (SourceRow r : carriers) {
            if (best == null) {
                best = r;
            } else if (r.createdDate != best.createdDate) {
                if (best.createdDate == null || (r.createdDate != null && r.createdDate > best.createdDate)) {
                    best = r;
                }
            } else if (
                r.sourceRecordId != null &&
                (best.sourceRecordId == null || r.sourceRecordId.compareTo(best.sourceRecordId) < 0)
            ) {
                best = r;
            }
        }
        return best;
    }

    @TestVisible
    private static String winnerBasis(SourceRow winner, List<SourceRow> carriers, String attributedId) {
        if (String.isNotBlank(attributedId) && attributedId.equalsIgnoreCase(winner.sourceRecordId)) {
            return 'The unified record is attributed to this source record by the ruleset.';
        }
        if (carriers.size() <= 1) {
            return 'This is the only contributing record carrying the winning value.';
        }
        return 'Most recently created of the records carrying the winning value.';
    }

    @TestVisible
    private static Map<String, List<String>> sourceIdCache = new Map<String, List<String>>();

    private static List<String> sourceRecordIds(String unifiedId, String linkDmo) {
        if (String.isBlank(unifiedId)) {
            return new List<String>();
        }
        String cacheKey = linkDmo + '|' + unifiedId;
        if (sourceIdCache.containsKey(cacheKey)) {
            return sourceIdCache.get(cacheKey);
        }

        List<String> ids = new List<String>();
        for (SObject link : safeQuery(
            'SELECT SourceRecordId__c FROM ' +
                safeName(linkDmo) +
                ' WHERE UnifiedRecordId__c = :uid LIMIT ' +
                MAX_SOURCE_IDS,
            new Map<String, Object>{ 'uid' => unifiedId }
        )) {
            String v = str(link, 'SourceRecordId__c');
            if (String.isNotBlank(v)) {
                ids.add(v);
            }
        }
        sourceIdCache.put(cacheKey, ids);
        return ids;
    }

    /**
     * Builds one email event, skipping a row the other query has already contributed.
     *
     * Sources describe the same event differently. A connector names the action and points at a
     * bulk message; a file load names the engagement type and carries the email's own name. Each
     * field falls back to its counterpart so both kinds of row read the same on the timeline.
     */
    @TestVisible
    private static void addEmailEvent(
        List<TimelineEvent> events,
        Set<String> seen,
        Set<String> bulkMessageIds,
        Map<String, Object> e
    ) {
        String rowId = str(e, 'ssot__Id__c');
        if (String.isNotBlank(rowId) && !seen.add(rowId)) {
            return;
        }

        TimelineEvent ev = new TimelineEvent();
        ev.id = rowId;
        ev.channel = 'Email';
        ev.sourceIndividualId = str(e, 'ssot__IndividualId__c');
        ev.eventDateTime = (Datetime) e.get('ssot__EngagementDateTm__c');

        String action = str(e, 'ssot__EngagementChannelActionId__c');
        if (String.isBlank(action)) {
            action = str(e, 'ssot__EngagementTypeId__c');
        }
        ev.eventType = friendlyAction(action, 'Email');
        ev.iconName = emailIcon(action);
        ev.detail = str(e, 'ssot__LinkName__c');

        String bulkId = str(e, 'ssot__BulkEmailMessageId__c');
        if (String.isNotBlank(bulkId)) {
            ev.campaignName = bulkId;
            bulkMessageIds.add(bulkId);
        } else {
            ev.campaignName = str(e, 'ssot__EmailName__c');
        }

        events.add(ev);
    }

    @TestVisible
    private static Map<String, List<String>> emailAddressCache = new Map<String, List<String>>();

    /** Every address the contributing records carry, winning or not. */
    private static List<String> profileEmailAddresses(String unifiedId, List<String> srcIds) {
        if (emailAddressCache.containsKey(unifiedId)) {
            return emailAddressCache.get(unifiedId);
        }

        Set<String> addresses = new Set<String>();
        for (Map<String, Object> cp : mapped(
            safeQuery(
                'SELECT ssot__EmailAddress__c FROM ' +
                    safeName(UnifiedProfileRegistry.SRC_EMAIL) +
                    ' WHERE ssot__PartyId__c IN :ids LIMIT ' +
                    MAX_SOURCE_IDS,
                new Map<String, Object>{ 'ids' => srcIds }
            )
        )) {
            String address = str(cp, 'ssot__EmailAddress__c');
            if (String.isNotBlank(address)) {
                addresses.add(address);
            }
        }

        List<String> result = new List<String>(addresses);
        emailAddressCache.put(unifiedId, result);
        return result;
    }

    private static void resolveCampaignNames(List<TimelineEvent> events, Set<String> bulkMessageIds) {
        if (bulkMessageIds.isEmpty()) {
            return;
        }
        Map<String, String> nameById = new Map<String, String>();
        List<String> ids = new List<String>(bulkMessageIds);
        for (Map<String, Object> m : mapped(
            safeQuery(
                'SELECT ssot__Id__c, ssot__Name__c FROM ' +
                    safeName(UnifiedProfileRegistry.BULK_EMAIL_MESSAGE) +
                    ' WHERE ssot__Id__c IN :ids LIMIT ' +
                    MAX_SOURCE_IDS,
                new Map<String, Object>{ 'ids' => ids }
            )
        )) {
            nameById.put(str(m, 'ssot__Id__c'), str(m, 'ssot__Name__c'));
        }
        applyCampaignNames(events, nameById);
    }

    @TestVisible
    private static void applyCampaignNames(List<TimelineEvent> events, Map<String, String> nameById) {
        if (nameById.isEmpty()) {
            return;
        }
        for (TimelineEvent ev : events) {
            if (ev.campaignName != null && nameById.containsKey(ev.campaignName)) {
                String resolved = nameById.get(ev.campaignName);
                if (String.isNotBlank(resolved)) {
                    ev.campaignName = resolved;
                }
            }
        }
    }

    /**
     * DMO availability varies by data space and ruleset, so a missing object or field must
     * degrade to an empty panel rather than break the whole page.
     */
    private static List<SObject> safeQuery(String soql, Map<String, Object> binds) {
        List<SObject> rows = queryOrNull(soql, binds);
        return rows == null ? new List<SObject>() : rows;
    }

    /** Null for a query the org could not run, so a caller can retry without the missing column. */
    private static List<SObject> queryOrNull(String soql, Map<String, Object> binds) {
        try {
            return Database.queryWithBinds(soql, binds, AccessLevel.SYSTEM_MODE);
        } catch (Exception e) {
            return null;
        }
    }

    private static String safeName(String apiName) {
        if (String.isBlank(apiName) || !SAFE_NAME.matcher(apiName).matches()) {
            throw new AuraHandledException('Invalid object or field name: ' + apiName);
        }
        return apiName;
    }

    @TestVisible
    private static Integer boundRows(Integer requested) {
        if (requested == null || requested <= 0) {
            return DEFAULT_TIMELINE_ROWS;
        }
        return Math.min(requested, MAX_TIMELINE_ROWS);
    }

    private static String str(SObject row, String field) {
        Object v = row.get(field);
        return v == null ? null : String.valueOf(v);
    }

    /**
     * Query rows are read as plain maps of column to value. Data Cloud objects cannot be created
     * in a test, so keeping the mapping logic off the SObject is what lets it be exercised.
     */
    private static List<Map<String, Object>> mapped(List<SObject> rows) {
        List<Map<String, Object>> values = new List<Map<String, Object>>();
        for (SObject row : rows) {
            values.add(row.getPopulatedFieldsAsMap());
        }
        return values;
    }

    private static String str(Map<String, Object> row, String field) {
        Object v = row.get(field);
        return v == null ? null : String.valueOf(v);
    }

    /** Several source systems populate first and last name with the same full-name string. */
    @TestVisible
    private static String displayName(String personName, String first, String last) {
        if (String.isNotBlank(personName)) {
            return personName;
        }
        String f = first == null ? '' : first.trim();
        String l = last == null ? '' : last.trim();
        if (String.isBlank(l) || f.equalsIgnoreCase(l)) {
            return String.isBlank(f) ? l : f;
        }
        return (f + ' ' + l).trim();
    }

    @TestVisible
    private static String renderContactPoint(Map<String, Object> cp, String type) {
        if (type == 'phone') {
            return str(cp, 'ssot__TelephoneNumber__c');
        }
        if (type == 'address') {
            List<String> parts = new List<String>();
            for (String f : new List<String>{
                'ssot__AddressLine1__c',
                'ssot__CityName__c',
                'ssot__StateProvinceName__c',
                'ssot__PostalCodeText__c'
            }) {
                String v = str(cp, f);
                if (String.isNotBlank(v)) {
                    parts.add(v);
                }
            }
            return String.join(parts, ', ');
        }
        return str(cp, 'ssot__EmailAddress__c');
    }

    private static String webEngagementSoql(Boolean withActionStatus, Integer cap) {
        return 'SELECT ssot__Id__c, ssot__IndividualId__c, ssot__EngagementDateTm__c,' +
            ' ssot__EngagementChannelActionId__c, ssot__EngagementTypeId__c,' +
            (withActionStatus ? ' ssot__EngmtChannelActionStatus__c,' : '') +
            ' ssot__UtmCampaignName__c, ssot__PagePublicTitleName__c, ssot__PageURL__c FROM ' +
            safeName(UnifiedProfileRegistry.WEB_ENGAGEMENT) +
            ' WHERE ssot__IndividualId__c IN :ids' +
            ' ORDER BY ssot__EngagementDateTm__c DESC LIMIT ' +
            cap;
    }

    /**
     * What the visitor did. Web tracking fills whichever of these three the source system knows:
     * the channel action where one is modelled, otherwise the action status, which is where a
     * page view or a form submit usually lands.
     */
    @TestVisible
    private static String webAction(Map<String, Object> row) {
        String action = str(row, 'ssot__EngagementChannelActionId__c');
        if (String.isBlank(action)) {
            action = str(row, 'ssot__EngmtChannelActionStatus__c');
        }
        if (String.isBlank(action)) {
            action = str(row, 'ssot__EngagementTypeId__c');
        }
        return action;
    }

    /**
     * Wording for an action code. The same code means different things per channel, so a click
     * reads as an email click on one and a web click on the other.
     */
    @TestVisible
    private static String friendlyAction(String action, String channel) {
        Boolean isWeb = 'Web'.equalsIgnoreCase(channel);
        if (String.isBlank(action)) {
            return isWeb ? 'Web Engagement' : 'Engagement';
        }

        // Sources spell the same action as PAGE_VIEW or "Page View", so both reach one label.
        String code = action.toUpperCase().replace(' ', '_');
        if (isWeb) {
            switch on code {
                when 'PAGE_VIEW', 'PAGEVIEW', 'VIEW' {
                    return 'Page View';
                }
                when 'CLICK', 'CLICKED', 'LINK_CLICK' {
                    return 'Web Click';
                }
                when else {
                    return prettify(action);
                }
            }
        }

        switch on code {
            when 'SEND_STATUS', 'SENT', 'SEND' {
                return 'Email Sent';
            }
            when 'OPEN', 'OPENED' {
                return 'Email Open';
            }
            when 'CLICK', 'CLICKED' {
                return 'Email Click';
            }
            when 'BOUNCE', 'BOUNCED' {
                return 'Email Bounce';
            }
            when 'UNSUBSCRIBE', 'UNSUBSCRIBED' {
                return 'Unsubscribed';
            }
            when else {
                return prettify(action);
            }
        }
    }

    @TestVisible
    private static String emailIcon(String action) {
        String a = String.isBlank(action) ? '' : action.toUpperCase();
        if (a.contains('OPEN')) {
            return 'utility:preview';
        }
        if (a.contains('CLICK')) {
            return 'utility:link';
        }
        if (a.contains('BOUNCE')) {
            return 'utility:warning';
        }
        if (a.contains('UNSUB')) {
            return 'utility:ban';
        }
        return 'utility:email';
    }

    @TestVisible
    private static String prettify(String raw) {
        String cleaned = raw.replace('_', ' ').toLowerCase().trim();
        List<String> words = new List<String>();
        for (String w : cleaned.split(' ')) {
            if (String.isNotBlank(w)) {
                words.add(w.substring(0, 1).toUpperCase() + w.substring(1));
            }
        }
        return String.join(words, ' ');
    }
}
