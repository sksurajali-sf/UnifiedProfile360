/**
 * Lets the page reach any Data Cloud object that hangs off the individual, without knowing
 * that object in advance.
 *
 * The catalogue comes from the Data Cloud metadata service rather than Apex describes, because
 * DMOs are absent from getGlobalDescribe and from EntityDefinition, and because the service
 * reports each object's mapped fields and its relationships to other objects. Mapped fields are
 * exactly the ones worth offering: Sales Order describes 165 columns but only 21 hold anything.
 */
public with sharing class UnifiedDmoExplorerController {
    private static final Integer MAX_ROWS = 100;
    private static final Pattern SAFE_NAME = Pattern.compile('^[A-Za-z0-9_]+$');

    /*
     * The metadata service hands back objects that are not Apex maps: casting one crashes the
     * request and serializing one fails, leaving toString as the only way in. These patterns read
     * that rendering. Every value they capture is an API name, a type keyword or a label that
     * runs up to a known key, so nothing depends on the order the keys come out in.
     */
    private static final Pattern ENTITY_NAME = Pattern.compile('name=([A-Za-z0-9_]+__dlm), displayName=(.*?), [a-zA-Z]+=');
    private static final Pattern ENTITY_CATEGORY = Pattern.compile('category=([A-Za-z_]+)');
    private static final Pattern BLOCK_FIELDS = Pattern.compile('fields=\\[(.*?)\\]');
    private static final Pattern BLOCK_RELATIONSHIPS = Pattern.compile('relationships=\\[(.*?)\\]');
    private static final Pattern FIELD_ENTRY = Pattern.compile('\\{name=([A-Za-z0-9_]+), displayName=(.*?), type=([A-Z_]+)');
    private static final Pattern RELATIONSHIP_ENTRY = Pattern.compile(
        'fromEntity=([A-Za-z0-9_]+), toEntity=([A-Za-z0-9_]+), fromEntityAttribute=([A-Za-z0-9_]+), toEntityAttribute=([A-Za-z0-9_]+)'
    );

    /** DMOs a profile is built from, and so the ones a related object points at. */
    private static final Set<String> INDIVIDUAL_ROOTS = new Set<String>{
        'ssot__individual__dlm',
        'unifiedindividual__dlm'
    };

    public class ObjectOption {
        @AuraEnabled
        public String apiName;
        @AuraEnabled
        public String label;
        @AuraEnabled
        public String category;
        /** How this object reaches the individual, shown under the name in the picker. */
        @AuraEnabled
        public String relationship;
        /** Column that carries the individual reference, offered as the default key. */
        @AuraEnabled
        public String suggestedKey;
        @AuraEnabled
        public Boolean isDirect = false;
    }

    public class FieldOption {
        @AuraEnabled
        public String apiName;
        @AuraEnabled
        public String label;
        @AuraEnabled
        public String type;
    }

    public class ObjectDetail {
        @AuraEnabled
        public String apiName;
        @AuraEnabled
        public String label;
        @AuraEnabled
        public List<FieldOption> fields = new List<FieldOption>();
        @AuraEnabled
        public String suggestedKey;
    }

    public class ResultColumn {
        @AuraEnabled
        public String apiName;
        @AuraEnabled
        public String label;
        @AuraEnabled
        public String type;
    }

    public class ResultRow {
        @AuraEnabled
        public String key;
        @AuraEnabled
        public List<String> cells = new List<String>();
    }

    public class SearchResult {
        @AuraEnabled
        public List<ResultColumn> columns = new List<ResultColumn>();
        @AuraEnabled
        public List<ResultRow> rows = new List<ResultRow>();
        /** Column the newest-first ordering used, blank when the object has no date to sort on. */
        @AuraEnabled
        public String orderedBy;
        @AuraEnabled
        public Boolean truncated = false;
        @AuraEnabled
        public String notice;
    }

    // ------------------------------------------------------------------
    // Endpoints
    // ------------------------------------------------------------------

    /**
     * Objects related to the individual behind this page, directly or through one intermediate
     * object. One hop is what brings in Sales Order and Opportunity, which reach the individual
     * through Account Contact rather than naming it themselves.
     */
    @AuraEnabled
    public static List<ObjectOption> getRelatedObjects(String objectApiName) {
        Map<String, Entity> catalogue = catalogue();
        if (catalogue.isEmpty()) {
            return new List<ObjectOption>();
        }

        Set<String> roots = individualRoots(objectApiName);
        Map<String, ObjectOption> options = new Map<String, ObjectOption>();

        for (Entity entity : catalogue.values()) {
            if (roots.contains(entity.apiName.toLowerCase())) {
                continue;
            }

            for (Relationship rel : entity.relationships) {
                String other = otherEntity(rel, entity.apiName);
                if (other == null || !roots.contains(other.toLowerCase())) {
                    continue;
                }
                ObjectOption option = option(entity);
                option.isDirect = true;
                option.suggestedKey = ownAttribute(rel, entity.apiName);
                option.relationship = 'Points at ' + label(catalogue, other);
                options.put(entity.apiName, option);
                break;
            }
        }

        // Second pass, so an object already reachable directly is never demoted to a hop.
        for (Entity entity : catalogue.values()) {
            if (options.containsKey(entity.apiName) || roots.contains(entity.apiName.toLowerCase())) {
                continue;
            }

            for (Relationship rel : entity.relationships) {
                String other = otherEntity(rel, entity.apiName);
                if (other == null || !options.containsKey(other)) {
                    continue;
                }
                ObjectOption option = option(entity);
                option.suggestedKey = ownAttribute(rel, entity.apiName);
                option.relationship = 'Reaches the individual through ' + label(catalogue, other);
                options.put(entity.apiName, option);
                break;
            }
        }

        List<ObjectOption> sorted = options.values();
        sorted.sort(new ByLabel());
        return sorted;
    }

    /** Mapped fields of one object, which are the only ones that can hold a value. */
    @AuraEnabled
    public static ObjectDetail describeObject(String dmoApiName, String objectApiName) {
        ObjectDetail detail = new ObjectDetail();
        Entity entity = catalogue().get(dmoApiName);
        if (entity == null) {
            throw new AuraHandledException('Unknown data model object: ' + dmoApiName);
        }

        detail.apiName = dmoApiName;
        detail.label = entity.label;
        for (Field field : entity.fields) {
            // Key qualifiers exist to disambiguate ids across systems and read as noise here.
            if (field.apiName.startsWith('KQ_')) {
                continue;
            }
            FieldOption option = new FieldOption();
            option.apiName = field.apiName;
            option.label = field.label;
            option.type = field.type;
            detail.fields.add(option);
        }
        detail.fields.sort(new FieldsByLabel());

        Set<String> roots = individualRoots(objectApiName);
        for (Relationship rel : entity.relationships) {
            String other = otherEntity(rel, dmoApiName);
            if (other != null && roots.contains(other.toLowerCase())) {
                detail.suggestedKey = ownAttribute(rel, dmoApiName);
                break;
            }
        }
        return detail;
    }

    /**
     * Rows of the chosen object whose key column names this profile, newest first.
     *
     * Names are checked against the catalogue rather than escaped, so only columns the service
     * itself reported can reach the SQL. The ids are the profile's own, quoted and escaped.
     */
    @AuraEnabled
    public static SearchResult search(
        String recordId,
        String objectApiName,
        String dmoApiName,
        List<String> fieldNames,
        String keyColumn,
        Integer rowLimit
    ) {
        SearchResult result = new SearchResult();
        Entity entity = catalogue().get(dmoApiName);
        if (entity == null) {
            throw new AuraHandledException('Unknown data model object: ' + dmoApiName);
        }

        // As many columns as the object holds; the table scrolls sideways rather than shrinking.
        Map<String, Field> byName = fieldsByName(entity);
        List<String> columns = new List<String>();
        Set<String> taken = new Set<String>();
        for (String requested : fieldNames == null ? new List<String>() : fieldNames) {
            if (byName.containsKey(requested) && taken.add(requested)) {
                columns.add(requested);
            }
        }
        if (columns.isEmpty() || !byName.containsKey(keyColumn)) {
            throw new AuraHandledException('Choose at least one field and a key column.');
        }

        for (String column : columns) {
            ResultColumn rc = new ResultColumn();
            rc.apiName = column;
            rc.label = byName.get(column).label;
            rc.type = byName.get(column).type;
            result.columns.add(rc);
        }

        List<String> ids = UnifiedProfileController.profileIdentifiers(recordId, objectApiName);
        if (ids.isEmpty()) {
            result.notice = 'This profile has no contributing records to match on.';
            return result;
        }

        // The key column is repeated in the select so a row can be traced back to the id it matched.
        List<String> selectList = new List<String>(columns);
        if (!selectList.contains(keyColumn)) {
            selectList.add(keyColumn);
        }

        String orderColumn = newestFirstColumn(entity, columns);
        result.orderedBy = orderColumn == null ? null : byName.get(orderColumn).label;

        Integer cap = rowLimit == null || rowLimit <= 0 ? MAX_ROWS : Math.min(rowLimit, MAX_ROWS);
        String sql =
            'SELECT ' +
            String.join(selectList, ', ') +
            ' FROM ' +
            safeName(dmoApiName) +
            ' WHERE ' +
            safeName(keyColumn) +
            ' IN (' +
            quotedList(ids) +
            ')' +
            (orderColumn == null ? '' : ' ORDER BY ' + orderColumn + ' DESC') +
            ' LIMIT ' +
            (cap + 1);

        List<List<Object>> rows;
        Map<String, Integer> placeByColumn;
        try {
            ConnectApi.CdpQueryInput input = new ConnectApi.CdpQueryInput();
            input.sql = sql;
            ConnectApi.CdpQueryOutputV2 output = ConnectApi.CdpQuery.queryAnsiSqlV2(input);

            placeByColumn = new Map<String, Integer>();
            if (output.metadata != null) {
                for (String column : output.metadata.keySet()) {
                    placeByColumn.put(column, output.metadata.get(column).placeInOrder);
                }
            }
            rows = new List<List<Object>>();
            if (output.data != null) {
                for (ConnectApi.CdpQueryV2Row row : output.data) {
                    rows.add(row.rowData);
                }
            }
        } catch (Exception e) {
            throw new AuraHandledException('Data Cloud could not run that query: ' + e.getMessage());
        }

        if (rows.size() > cap) {
            result.truncated = true;
            while (rows.size() > cap) {
                rows.remove(rows.size() - 1);
            }
        }

        addRows(result, rows, columns, placeByColumn, byName, dmoApiName);

        if (result.rows.isEmpty()) {
            result.notice = 'No rows on this object name this profile through that column.';
        }
        return result;
    }

    /** Lays each returned row out under the headings the user chose, in that order. */
    @TestVisible
    private static void addRows(
        SearchResult result,
        List<List<Object>> rows,
        List<String> columns,
        Map<String, Integer> placeByColumn,
        Map<String, Field> byName,
        String dmoApiName
    ) {
        Integer index = 0;
        for (List<Object> row : rows) {
            ResultRow rr = new ResultRow();
            rr.key = dmoApiName + '-' + index++;
            for (String column : columns) {
                Integer at = placeByColumn.get(column);
                Object value = at == null || at >= row.size() ? null : row[at];
                // An empty column holds a blank, never a null: the serialiser drops nulls out of
                // a list, which would slide every later value one column left of its heading.
                rr.cells.add(value == null ? '' : normalise(String.valueOf(value), byName.get(column)));
            }
            result.rows.add(rr);
        }
    }

    // ------------------------------------------------------------------
    // Catalogue
    // ------------------------------------------------------------------

    public class Entity {
        public String apiName;
        public String label;
        public String category;
        public List<Field> fields = new List<Field>();
        public List<Relationship> relationships = new List<Relationship>();
    }

    public class Field {
        public String apiName;
        public String label;
        public String type;
    }

    public class Relationship {
        public String fromEntity;
        public String toEntity;
        public String fromAttribute;
        public String toAttribute;
    }

    @TestVisible
    private static Map<String, Entity> cachedCatalogue;

    /**
     * Every data model object in the default data space, keyed by API name. One service call
     * covers the picker, the field list and the name checks the query relies on.
     */
    private static Map<String, Entity> catalogue() {
        if (cachedCatalogue != null) {
            return cachedCatalogue;
        }

        Map<String, Entity> entities = new Map<String, Entity>();
        try {
            ConnectApi.CdpQueryMetadataOutput output = ConnectApi.CdpQuery.getAllMetadata(
                'DataModelObject',
                null,
                null,
                null
            );
            if (output != null && output.metadata != null) {
                for (Object item : output.metadata) {
                    Entity entity = parseEntity(String.valueOf(item));
                    if (entity != null) {
                        entities.put(entity.apiName, entity);
                    }
                }
            }
        } catch (Exception e) {
            // No catalogue means an empty picker rather than a broken page.
        }

        cachedCatalogue = entities;
        return entities;
    }

    @TestVisible
    private static Entity parseEntity(String rendered) {
        if (String.isBlank(rendered)) {
            return null;
        }

        Matcher name = ENTITY_NAME.matcher(rendered);
        if (!name.find()) {
            return null;
        }

        Entity entity = new Entity();
        entity.apiName = name.group(1);
        entity.label = firstNonBlank(name.group(2), entity.apiName);

        Matcher category = ENTITY_CATEGORY.matcher(rendered);
        if (category.find()) {
            entity.category = category.group(1);
        }

        Matcher fieldBlock = BLOCK_FIELDS.matcher(rendered);
        if (fieldBlock.find()) {
            Matcher field = FIELD_ENTRY.matcher(fieldBlock.group(1));
            while (field.find()) {
                Field f = new Field();
                f.apiName = field.group(1);
                f.label = firstNonBlank(field.group(2), f.apiName);
                f.type = field.group(3);
                entity.fields.add(f);
            }
            distinguishLabels(entity.fields);
        }

        Matcher relationshipBlock = BLOCK_RELATIONSHIPS.matcher(rendered);
        if (relationshipBlock.find()) {
            Matcher rel = RELATIONSHIP_ENTRY.matcher(relationshipBlock.group(1));
            while (rel.find()) {
                Relationship r = new Relationship();
                r.fromEntity = rel.group(1);
                r.toEntity = rel.group(2);
                r.fromAttribute = rel.group(3);
                r.toAttribute = rel.group(4);
                entity.relationships.add(r);
            }
        }

        return entity;
    }

    /**
     * Two columns of one object can carry the same label - Consent Status is both a code and a
     * text column - leaving the picker with entries that cannot be told apart and the table with
     * two headings that read alike. Only the colliding ones take their api name alongside.
     */
    @TestVisible
    private static void distinguishLabels(List<Field> fields) {
        Map<String, Integer> tally = new Map<String, Integer>();
        for (Field f : fields) {
            String key = f.label == null ? '' : f.label.toLowerCase();
            Integer seen = tally.get(key);
            tally.put(key, seen == null ? 1 : seen + 1);
        }

        for (Field f : fields) {
            String key = f.label == null ? '' : f.label.toLowerCase();
            if (tally.get(key) > 1) {
                f.label = f.label + ' (' + shortName(f.apiName) + ')';
            }
        }
    }

    /** An api name without the wrapping the platform adds, short enough to sit in a heading. */
    @TestVisible
    private static String shortName(String apiName) {
        String name = apiName == null ? '' : apiName;
        if (name.startsWith('ssot__')) {
            name = name.substring(6);
        }
        return name.endsWith('__c') ? name.substring(0, name.length() - 3) : name;
    }

    /** The individual objects this page's profile is made of, plus the standard source individual. */
    @TestVisible
    private static Set<String> individualRoots(String objectApiName) {
        Set<String> roots = new Set<String>(INDIVIDUAL_ROOTS);
        UnifiedProfileRegistry.DmoSet dmo = UnifiedProfileRegistry.resolve(objectApiName);
        if (String.isNotBlank(dmo.unifiedIndividual)) {
            roots.add(dmo.unifiedIndividual.toLowerCase());
        }
        return roots;
    }

    private static ObjectOption option(Entity entity) {
        ObjectOption option = new ObjectOption();
        option.apiName = entity.apiName;
        option.label = entity.label;
        option.category = prettyCategory(entity.category);
        return option;
    }

    /**
     * Column the rows are ordered by. A date the user chose to display is the most useful, then
     * any date the object holds, so "latest 100" means something even on an object whose dates
     * were left out of the selection.
     */
    @TestVisible
    private static String newestFirstColumn(Entity entity, List<String> chosen) {
        Map<String, Field> byName = fieldsByName(entity);

        for (String column : chosen) {
            if (isDate(byName.get(column))) {
                return column;
            }
        }
        for (Field field : entity.fields) {
            if (isDate(field)) {
                return field.apiName;
            }
        }
        return null;
    }

    /**
     * The query service returns timestamps as "2026-06-05 08:00:44.857 UTC", which no date
     * formatter reads. ISO 8601 is what the page needs to show them in the viewer's own time zone.
     */
    @TestVisible
    private static String normalise(String value, Field field) {
        if (!isDate(field) || String.isBlank(value)) {
            return value;
        }
        String trimmed = value.trim();
        if (!trimmed.endsWith(' UTC')) {
            return trimmed;
        }
        return trimmed.removeEnd(' UTC').replaceFirst(' ', 'T') + 'Z';
    }

    @TestVisible
    private static Boolean isDate(Field field) {
        if (field == null || field.type == null) {
            return false;
        }
        return field.type.equalsIgnoreCase('DATE_TIME') || field.type.equalsIgnoreCase('DATE');
    }

    @TestVisible
    private static Map<String, Field> fieldsByName(Entity entity) {
        Map<String, Field> byName = new Map<String, Field>();
        for (Field field : entity.fields) {
            byName.put(field.apiName, field);
        }
        return byName;
    }

    /** The entity at the far end of a relationship, whichever side this object sits on. */
    @TestVisible
    private static String otherEntity(Relationship rel, String self) {
        if (self.equalsIgnoreCase(rel.fromEntity)) {
            return rel.toEntity;
        }
        return self.equalsIgnoreCase(rel.toEntity) ? rel.fromEntity : null;
    }

    /** This object's own side of a relationship, which is the column that carries the reference. */
    @TestVisible
    private static String ownAttribute(Relationship rel, String self) {
        return self.equalsIgnoreCase(rel.fromEntity) ? rel.fromAttribute : rel.toAttribute;
    }

    private static String label(Map<String, Entity> catalogue, String apiName) {
        Entity entity = catalogue.get(apiName);
        return entity == null ? apiName : entity.label;
    }

    @TestVisible
    private static String prettyCategory(String category) {
        if (String.isBlank(category)) {
            return null;
        }
        return category.replace('_', ' ');
    }

    private static String firstNonBlank(String preferred, String fallback) {
        return String.isNotBlank(preferred) ? preferred : fallback;
    }

    private static String safeName(String apiName) {
        if (String.isBlank(apiName) || !SAFE_NAME.matcher(apiName).matches()) {
            throw new AuraHandledException('Invalid object or field name: ' + apiName);
        }
        return apiName;
    }

    @TestVisible
    private static String quotedList(List<String> values) {
        List<String> quoted = new List<String>();
        for (String value : values) {
            if (String.isNotBlank(value)) {
                quoted.add('\'' + String.escapeSingleQuotes(value) + '\'');
            }
        }
        return String.join(quoted, ', ');
    }

    private class ByLabel implements Comparator<ObjectOption> {
        public Integer compare(ObjectOption a, ObjectOption b) {
            return a.label.compareTo(b.label);
        }
    }

    private class FieldsByLabel implements Comparator<FieldOption> {
        public Integer compare(FieldOption a, FieldOption b) {
            return a.label.compareTo(b.label);
        }
    }
}
