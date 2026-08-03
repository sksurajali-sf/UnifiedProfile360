/**
 * Backing controller for the custom Profile Explorer.
 *
 * Data Cloud objects are queryable through SOQL but are absent from getGlobalDescribe and
 * EntityDefinition, so they cannot be enumerated at runtime. The profile DMOs on offer are
 * therefore registered in ProfileExplorerDmo__mdt, while each DMO's fields are still read
 * dynamically through a targeted Schema.describeSObjects call.
 */
public with sharing class ProfileExplorerController {
    private static final Integer MAX_RESULTS = 50;
    private static final Integer MAX_ID_FANOUT = 200;
    private static final Pattern SAFE_NAME = Pattern.compile('^[A-Za-z0-9_]+$');

    /** Attribute groups mirror the standard explorer: direct fields, then related ones. */
    private static final String GROUP_DIRECT = 'Attributes';
    private static final String GROUP_RELATED = 'Related Attributes';

    private static final List<String> UNIFIED_FIELDS = new List<String>{
        'ssot__FirstName__c',
        'ssot__LastName__c',
        'ssot__PersonName__c',
        'ssot__Id__c'
    };

    public class DataSpaceOption {
        @AuraEnabled
        public String apiName;
        @AuraEnabled
        public String label;
    }

    public class DmoOption {
        @AuraEnabled
        public String apiName;
        @AuraEnabled
        public String label;
    }

    public class AttributeOption {
        @AuraEnabled
        public String key;
        @AuraEnabled
        public String label;
        @AuraEnabled
        public String groupLabel;
    }

    public class ProfileRow {
        @AuraEnabled
        public String unifiedId;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String matchedValue;
        @AuraEnabled
        public Datetime createdDate;
    }

    public class SearchOutcome {
        @AuraEnabled
        public List<ProfileRow> rows = new List<ProfileRow>();
        @AuraEnabled
        public Boolean truncated = false;
        @AuraEnabled
        public String matchedLabel;
        @AuraEnabled
        public String message;
    }

    // ------------------------------------------------------------------ pickers

    @AuraEnabled(cacheable=true)
    public static List<DataSpaceOption> getDataSpaces() {
        List<DataSpaceOption> options = new List<DataSpaceOption>();
        for (DataSpace space : [
            SELECT Name, DataSpaceApiName
            FROM DataSpace
            WHERE Status = 'ACTIVE'
            WITH USER_MODE
            ORDER BY Name
            LIMIT 100
        ]) {
            DataSpaceOption o = new DataSpaceOption();
            o.apiName = space.DataSpaceApiName;
            o.label = space.Name;
            options.add(o);
        }
        return options;
    }

    @AuraEnabled(cacheable=true)
    public static List<DmoOption> getProfileDmos(String dataSpaceApiName) {
        String space = String.isBlank(dataSpaceApiName) ? 'default' : dataSpaceApiName.trim();
        List<DmoOption> options = new List<DmoOption>();

        for (ProfileExplorerDmo__mdt row : [
            SELECT MasterLabel, DmoApiName__c
            FROM ProfileExplorerDmo__mdt
            WHERE IsActive__c = TRUE AND DataSpaceApiName__c = :space
            ORDER BY SortOrder__c NULLS LAST, MasterLabel
        ]) {
            DmoOption o = new DmoOption();
            o.apiName = row.DmoApiName__c;
            o.label = row.MasterLabel;
            options.add(o);
        }
        return options;
    }

    /**
     * Attribute keys are encoded as DMO|FIELD so the search knows whether to hit the unified
     * object directly or fan out through a related contact point object.
     */
    @AuraEnabled(cacheable=true)
    public static List<AttributeOption> getAttributes(String dmoApiName) {
        List<AttributeOption> options = new List<AttributeOption>();
        if (String.isBlank(dmoApiName)) {
            return options;
        }

        UnifiedProfileRegistry.DmoSet dmo = UnifiedProfileRegistry.resolve(dmoApiName);

        Map<String, String> unifiedLabels = fieldLabels(dmo.unifiedIndividual);
        for (String field : UNIFIED_FIELDS) {
            if (unifiedLabels.containsKey(field)) {
                options.add(attribute(dmo.unifiedIndividual, field, unifiedLabels.get(field), GROUP_DIRECT));
            }
        }

        addRelated(options, dmo.unifiedEmail, new List<String>{ 'ssot__EmailAddress__c' });
        addRelated(
            options,
            dmo.unifiedPhone,
            new List<String>{ 'ssot__FormattedE164PhoneNumber__c', 'ssot__TelephoneNumber__c' }
        );
        addRelated(
            options,
            dmo.unifiedAddress,
            new List<String>{
                'ssot__AddressLine1__c',
                'ssot__CityName__c',
                'ssot__StateProvinceName__c',
                'ssot__PostalCodeText__c',
                'ssot__CountryName__c'
            }
        );

        return options;
    }

    // ------------------------------------------------------------------ search

    @AuraEnabled(cacheable=true)
    public static SearchOutcome searchProfiles(String dmoApiName, String attributeKey, String searchTerm) {
        SearchOutcome outcome = new SearchOutcome();

        if (String.isBlank(dmoApiName) || String.isBlank(attributeKey)) {
            outcome.message = 'Choose an object and an attribute to search.';
            return outcome;
        }
        if (String.isBlank(searchTerm) || searchTerm.trim().length() < 2) {
            outcome.message = 'Enter at least two characters to search.';
            return outcome;
        }

        List<String> parts = attributeKey.split('\\|');
        if (parts.size() != 2 || !SAFE_NAME.matcher(parts[0]).matches() || !SAFE_NAME.matcher(parts[1]).matches()) {
            outcome.message = 'That attribute is not searchable.';
            return outcome;
        }

        String targetDmo = parts[0];
        String targetField = parts[1];
        UnifiedProfileRegistry.DmoSet dmo = UnifiedProfileRegistry.resolve(dmoApiName);
        String pattern = '%' + String.escapeSingleQuotes(searchTerm.trim()) + '%';
        outcome.matchedLabel = fieldLabels(targetDmo).get(targetField);

        Map<String, String> matchedById = new Map<String, String>();
        Boolean searchingUnified = targetDmo == dmo.unifiedIndividual;

        if (searchingUnified) {
            matchedById = matches(
                mapped(
                    safeQuery(
                        'SELECT ssot__Id__c, ' +
                            targetField +
                            ' FROM ' +
                            targetDmo +
                            ' WHERE ' +
                            targetField +
                            ' LIKE :pattern LIMIT ' +
                            (MAX_RESULTS + 1),
                        new Map<String, Object>{ 'pattern' => pattern }
                    )
                ),
                'ssot__Id__c',
                targetField
            );
        } else {
            // Contact point objects carry the unified id in ssot__PartyId__c.
            matchedById = matches(
                mapped(
                    safeQuery(
                        'SELECT ssot__PartyId__c, ' +
                            targetField +
                            ' FROM ' +
                            targetDmo +
                            ' WHERE ' +
                            targetField +
                            ' LIKE :pattern LIMIT ' +
                            MAX_ID_FANOUT,
                        new Map<String, Object>{ 'pattern' => pattern }
                    )
                ),
                'ssot__PartyId__c',
                targetField
            );
        }

        if (matchedById.isEmpty()) {
            outcome.message = 'No profiles matched that search.';
            return outcome;
        }

        List<String> ids = new List<String>(matchedById.keySet());
        if (ids.size() > MAX_RESULTS) {
            outcome.truncated = true;
            List<String> trimmed = new List<String>();
            for (Integer i = 0; i < MAX_RESULTS; i++) {
                trimmed.add(ids[i]);
            }
            ids = trimmed;
        }

        outcome.rows = profileRows(
            mapped(
                safeQuery(
                    'SELECT ssot__Id__c, ssot__FirstName__c, ssot__LastName__c, ssot__PersonName__c,' +
                        ' ssot__CreatedDate__c FROM ' +
                        dmo.unifiedIndividual +
                        ' WHERE ssot__Id__c IN :ids LIMIT ' +
                        MAX_RESULTS,
                    new Map<String, Object>{ 'ids' => ids }
                )
            ),
            matchedById
        );

        if (outcome.rows.isEmpty()) {
            outcome.message = 'No profiles matched that search.';
        }
        return outcome;
    }

    /** Unified id to the value that matched it, keeping the first hit per profile. */
    @TestVisible
    private static Map<String, String> matches(List<Map<String, Object>> rows, String idField, String valueField) {
        Map<String, String> matchedById = new Map<String, String>();
        for (Map<String, Object> row : rows) {
            String uid = str(row, idField);
            if (String.isNotBlank(uid) && !matchedById.containsKey(uid)) {
                matchedById.put(uid, str(row, valueField));
            }
        }
        return matchedById;
    }

    @TestVisible
    private static List<ProfileRow> profileRows(List<Map<String, Object>> rows, Map<String, String> matchedById) {
        List<ProfileRow> profiles = new List<ProfileRow>();
        for (Map<String, Object> row : rows) {
            ProfileRow p = new ProfileRow();
            p.unifiedId = str(row, 'ssot__Id__c');
            p.name = displayName(
                str(row, 'ssot__PersonName__c'),
                str(row, 'ssot__FirstName__c'),
                str(row, 'ssot__LastName__c')
            );
            p.matchedValue = matchedById.get(p.unifiedId);
            p.createdDate = (Datetime) row.get('ssot__CreatedDate__c');
            profiles.add(p);
        }
        return profiles;
    }

    // ------------------------------------------------------------------ helpers

    private static void addRelated(List<AttributeOption> options, String dmoName, List<String> fields) {
        if (String.isBlank(dmoName)) {
            return;
        }
        Map<String, String> labels = fieldLabels(dmoName);
        for (String field : fields) {
            if (labels.containsKey(field)) {
                options.add(attribute(dmoName, field, labels.get(field), GROUP_RELATED));
            }
        }
    }

    private static AttributeOption attribute(String dmoName, String field, String label, String groupLabel) {
        AttributeOption o = new AttributeOption();
        o.key = dmoName + '|' + field;
        o.label = label;
        o.groupLabel = groupLabel;
        return o;
    }

    private static Map<String, Map<String, String>> labelCache = new Map<String, Map<String, String>>();

    /** Text fields only; those are the ones a LIKE search can be run against. */
    @TestVisible
    private static Map<String, String> fieldLabels(String dmoName) {
        if (labelCache.containsKey(dmoName)) {
            return labelCache.get(dmoName);
        }

        Map<String, String> labels = new Map<String, String>();
        try {
            List<Schema.DescribeSObjectResult> described = Schema.describeSObjects(new List<String>{ dmoName });
            for (Schema.SObjectField f : described[0].fields.getMap().values()) {
                Schema.DescribeFieldResult fd = f.getDescribe();
                if (fd.isFilterable() && fd.getType() == Schema.DisplayType.STRING) {
                    labels.put(fd.getName(), fd.getLabel());
                }
            }
        } catch (Exception e) {
            // A ruleset may not have every contact point object; skip it rather than fail.
        }

        labelCache.put(dmoName, labels);
        return labels;
    }

    private static List<SObject> safeQuery(String soql, Map<String, Object> binds) {
        try {
            return Database.queryWithBinds(soql, binds, AccessLevel.USER_MODE);
        } catch (Exception e) {
            return new List<SObject>();
        }
    }

    /** Rows are read as plain maps, so the mapping can be exercised without a Data Cloud object. */
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

    @TestVisible
    private static String displayName(String personName, String firstName, String lastName) {
        if (String.isNotBlank(personName)) {
            return personName.trim();
        }
        String first = firstName == null ? '' : firstName.trim();
        String last = lastName == null ? '' : lastName.trim();
        if (first.equalsIgnoreCase(last)) {
            return String.isBlank(first) ? null : first;
        }
        String combined = (first + ' ' + last).trim();
        return String.isBlank(combined) ? null : combined;
    }
}
