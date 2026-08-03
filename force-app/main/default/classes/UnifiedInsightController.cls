/**
 * Calculated Insight access for the enhanced Profile Explorer page.
 *
 * Calculated Insights (__cio) are not exposed to SOQL, which is why they cannot be read
 * the same way as DMOs. They are reachable through the Data Cloud query service, which is
 * the same surface the standard Calculated Insights component uses.
 *
 * Methods are not cacheable because the underlying query service performs a callout.
 */
public with sharing class UnifiedInsightController {
    private static final Pattern SAFE_NAME = Pattern.compile('^[A-Za-z0-9_]+$');
    private static final Set<String> NUMERIC_TYPES = new Set<String>{
        'DECIMAL',
        'DOUBLE',
        'FLOAT',
        'INTEGER',
        'BIGINT',
        'NUMERIC',
        'REAL',
        'SMALLINT'
    };

    /**
     * Each candidate insight costs one query service callout to inspect, so the catalogue is
     * capped. Orgs with more insights than this should narrow the list rather than wait.
     */
    private static final Integer MAX_INSIGHTS_INSPECTED = 15;

    /** Dimension-keyed insights return one row per dimension combination. */
    private static final Integer MAX_ROWS = 50;

    public class InsightOption {
        @AuraEnabled
        public String apiName;
        @AuraEnabled
        public String label;
        @AuraEnabled
        public String keyField;
    }

    public class InsightField {
        @AuraEnabled
        public String apiName;
        @AuraEnabled
        public String label;
        @AuraEnabled
        public String textValue;
        @AuraEnabled
        public Decimal value;
        @AuraEnabled
        public Boolean isNumber = false;
    }

    public class InsightRow {
        @AuraEnabled
        public String key;
        @AuraEnabled
        public List<InsightField> dimensions = new List<InsightField>();
        @AuraEnabled
        public List<InsightField> measures = new List<InsightField>();
    }

    public class InsightResult {
        @AuraEnabled
        public String apiName;
        @AuraEnabled
        public String label;
        @AuraEnabled
        public String keyField;
        @AuraEnabled
        public Boolean found = false;
        @AuraEnabled
        public String message;
        @AuraEnabled
        public List<InsightRow> rows = new List<InsightRow>();
    }

    /**
     * Lists every calculated insight in the org that is keyed by a unified individual, so the
     * picker reflects the platform rather than a configured list.
     *
     * @param insightApiNames Comma separated fallback used only when the insight catalogue
     *                        cannot be read, which keeps older page configurations working.
     */
    @AuraEnabled
    public static List<InsightOption> getInsightOptions(String insightApiNames) {
        List<String> candidates = catalogueApiNames();
        if (candidates.isEmpty()) {
            candidates = splitNames(insightApiNames);
        }

        List<InsightOption> options = new List<InsightOption>();
        for (String apiName : candidates) {
            if (options.size() >= MAX_INSIGHTS_INSPECTED) {
                break;
            }
            // An insight known not to be keyed by a unified individual cannot be shown against
            // this profile. One that could not be inspected is kept, so a transient query
            // service failure empties nothing.
            String keyField = keyFieldFor(apiName);
            if (String.isBlank(keyField) && !probeFailed.contains(apiName)) {
                continue;
            }
            InsightOption o = new InsightOption();
            o.apiName = apiName;
            o.label = prettify(apiName);
            o.keyField = keyField;
            options.add(o);
        }
        return options;
    }

    @AuraEnabled
    public static InsightResult getInsightData(String ciApiName, String recordId, String objectApiName) {
        InsightResult result = new InsightResult();
        result.apiName = ciApiName;
        result.label = prettify(ciApiName);

        if (String.isBlank(ciApiName) || !SAFE_NAME.matcher(ciApiName).matches()) {
            result.message = 'Select a calculated insight.';
            return result;
        }

        String unifiedId = UnifiedProfileController.resolveUnifiedIdFor(recordId, objectApiName);
        if (String.isBlank(unifiedId)) {
            result.message = 'This profile has no unified id.';
            return result;
        }

        result.keyField = keyFieldFor(ciApiName);
        if (String.isBlank(result.keyField)) {
            result.message = result.label + ' is not keyed by a unified individual id.';
            return result;
        }

        try {
            applyRows(
                result,
                runSql(
                    'SELECT * FROM ' +
                        ciApiName +
                        ' WHERE ' +
                        result.keyField +
                        ' = \'' +
                        escapeLiteral(unifiedId) +
                        '\' LIMIT ' +
                        MAX_ROWS
                ),
                ciApiName
            );
        } catch (Exception e) {
            result.message = 'Unable to read ' + result.label + ': ' + e.getMessage();
        }

        return result;
    }

    // ------------------------------------------------------------------

    /**
     * Turns what the query service returned into the rows the panel shows. A dimension-keyed
     * insight comes back as one row per combination, and a row holding nothing worth showing is
     * left out rather than rendered empty.
     */
    @TestVisible
    private static void applyRows(InsightResult result, ConnectApi.CdpQueryOutputV2 data, String ciApiName) {
        if (data == null || data.data == null || data.data.isEmpty()) {
            result.message = 'No ' + result.label + ' value for this profile.';
            return;
        }

        Map<Integer, String> columns = orderedColumns(data);
        Map<String, String> types = columnTypes(data);

        for (Integer r = 0; r < data.data.size(); r++) {
            InsightRow row = buildRow(data.data[r].rowData, columns, types, result.keyField);
            if (!row.measures.isEmpty() || !row.dimensions.isEmpty()) {
                row.key = ciApiName + '-' + r;
                result.rows.add(row);
            }
        }

        result.found = !result.rows.isEmpty();
        if (!result.found) {
            result.message = result.label + ' has no measures to show.';
        }
    }

    @TestVisible
    private static InsightRow buildRow(
        List<Object> values,
        Map<Integer, String> columns,
        Map<String, String> types,
        String keyField
    ) {
        InsightRow row = new InsightRow();

        for (Integer i = 0; i < columns.size(); i++) {
            String column = columns.get(i);
            if (column == null || column == keyField || isNoise(column)) {
                continue;
            }

            Object raw = i < values.size() ? values[i] : null;
            InsightField f = new InsightField();
            f.apiName = column;
            f.label = prettify(column);

            if (NUMERIC_TYPES.contains(types.get(column))) {
                f.isNumber = true;
                f.value = toDecimal(raw);
                row.measures.add(f);
            } else {
                f.textValue = raw == null ? null : String.valueOf(raw);
                // A dimension with no value tells the user nothing.
                if (String.isNotBlank(f.textValue)) {
                    row.dimensions.add(f);
                }
            }
        }
        return row;
    }

    /** Key-qualifier and plumbing columns are internal and never meaningful on screen. */
    @TestVisible
    private static Boolean isNoise(String column) {
        String c = column.toLowerCase();
        return c.startsWith('kq_') || c.endsWith('_kq__c') || c.startsWith('cdp_sys_');
    }

    /**
     * Reads the insight catalogue and derives each API name from its label, which is how
     * Data Cloud names the queryable object. Returns empty when the catalogue is unavailable.
     */
    @TestVisible
    private static List<String> catalogueApiNames() {
        List<String> names = new List<String>();
        try {
            for (SObject ci : Database.query('SELECT Name FROM MktCalculatedInsight LIMIT 200')) {
                String label = (String) ci.get('Name');
                if (String.isBlank(label)) {
                    continue;
                }
                String apiName = label.trim().replaceAll('\\s+', '_') + '__cio';
                if (SAFE_NAME.matcher(apiName).matches()) {
                    names.add(apiName);
                }
            }
        } catch (Exception e) {
            return new List<String>();
        }
        names.sort();
        return names;
    }

    /** Blank value means inspected and unkeyed, which is different from never inspected. */
    @TestVisible
    private static Map<String, String> keyFieldCache = new Map<String, String>();
    private static Set<String> probeFailed = new Set<String>();

    /** Returns the unified individual column on an insight, or null when it has none. */
    @TestVisible
    private static String keyFieldFor(String ciApiName) {
        if (keyFieldCache.containsKey(ciApiName) || probeFailed.contains(ciApiName)) {
            return keyFieldCache.get(ciApiName);
        }

        try {
            ConnectApi.CdpQueryOutputV2 probe = runSql('SELECT * FROM ' + ciApiName + ' LIMIT 1');
            String keyField = findKeyField(orderedColumns(probe).values());
            keyFieldCache.put(ciApiName, keyField == null ? '' : keyField);
            return keyField;
        } catch (Exception e) {
            probeFailed.add(ciApiName);
            return null;
        }
    }

    @TestVisible
    private static List<String> splitNames(String csv) {
        List<String> names = new List<String>();
        if (String.isBlank(csv)) {
            return names;
        }
        for (String raw : csv.split(',')) {
            String name = raw == null ? '' : raw.trim();
            if (String.isNotBlank(name) && SAFE_NAME.matcher(name).matches()) {
                names.add(name);
            }
        }
        return names;
    }

    private static ConnectApi.CdpQueryOutputV2 runSql(String sql) {
        ConnectApi.CdpQueryInput input = new ConnectApi.CdpQueryInput();
        input.sql = sql;
        return ConnectApi.CdpQuery.queryAnsiSqlV2(input);
    }

    private static Map<Integer, String> orderedColumns(ConnectApi.CdpQueryOutputV2 output) {
        Map<Integer, String> ordered = new Map<Integer, String>();
        if (output == null || output.metadata == null) {
            return ordered;
        }
        for (String column : output.metadata.keySet()) {
            ordered.put(output.metadata.get(column).placeInOrder, column);
        }
        return ordered;
    }

    private static Map<String, String> columnTypes(ConnectApi.CdpQueryOutputV2 output) {
        Map<String, String> types = new Map<String, String>();
        if (output == null || output.metadata == null) {
            return types;
        }
        for (String column : output.metadata.keySet()) {
            types.put(column, output.metadata.get(column).type);
        }
        return types;
    }

    @TestVisible
    private static String findKeyField(List<String> columns) {
        for (String column : columns) {
            String c = column.toLowerCase();
            if (c.contains('unified_individual_id') || c.contains('unifiedindividualid')) {
                return column;
            }
        }
        for (String column : columns) {
            String c = column.toLowerCase();
            if (c.contains('profile_id') && !c.contains('kq')) {
                return column;
            }
        }
        return null;
    }

    @TestVisible
    private static Decimal toDecimal(Object value) {
        if (value == null) {
            return null;
        }
        try {
            return Decimal.valueOf(String.valueOf(value));
        } catch (Exception e) {
            return null;
        }
    }

    @TestVisible
    private static String escapeLiteral(String value) {
        return value.replace('\'', '\'\'');
    }

    @TestVisible
    private static String prettify(String raw) {
        if (String.isBlank(raw)) {
            return '';
        }
        String cleaned = raw.replace('__cio', '').replace('__c', '').replace('_', ' ').trim();
        List<String> words = new List<String>();
        for (String w : cleaned.split(' ')) {
            if (String.isNotBlank(w)) {
                words.add(w.substring(0, 1).toUpperCase() + w.substring(1));
            }
        }
        return String.join(words, ' ');
    }
}
