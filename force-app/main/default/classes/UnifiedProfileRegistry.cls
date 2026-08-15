/**
 * Resolves the family of Data Cloud DMOs that belong to a single Identity Resolution
 * ruleset, starting from the Unified Individual DMO the record page is rendering.
 *
 * Two things vary between orgs and both are handled here.
 *
 * The ruleset a profile came from decides the names of its unified and link objects, so one
 * data space can hold UnifiedIndividual__dlm alongside UnifiedssotIndividualMc__dlm and
 * UnifiedssotIndividualPoc1__dlm. The suffix is read off the bound DMO name at runtime.
 *
 * A data space stamps its own prefix onto every object it contains, turning
 * ssot__Individual__dlm into something like apj_Individual__dlm. That prefix is chosen when the
 * objects are created and is stored nowhere else: the DataSpace record does not carry it, and it
 * need not resemble the data space name (a space called DataSpace2 can prefix with DS1_). It can
 * therefore only be read back off a name we already know, which is the bound DMO the page was
 * opened on. Every other name is offered as a short list of candidates and the one the org
 * actually has is picked, rather than assuming a spelling that may not exist.
 */
public with sharing class UnifiedProfileRegistry {
    public static final String SRC_INDIVIDUAL = 'ssot__Individual__dlm';
    public static final String SRC_EMAIL = 'ssot__ContactPointEmail__dlm';
    public static final String SRC_PHONE = 'ssot__ContactPointPhone__dlm';
    public static final String SRC_ADDRESS = 'ssot__ContactPointAddress__dlm';

    public static final String EMAIL_ENGAGEMENT = 'ssot__EmailEngagement__dlm';
    public static final String WEB_ENGAGEMENT = 'ssot__WebsiteEngagement__dlm';
    public static final String BULK_EMAIL_MESSAGE = 'ssot__BulkEmailMessage__dlm';
    public static final String SALES_ORDER = 'ssot__SalesOrder__dlm';

    private static final String DEFAULT_UNIFIED = 'UnifiedIndividual__dlm';

    /**
     * Takes a Unified Individual DMO apart into the three things that vary.
     *
     *   UnifiedIndividual__dlm            prefix ""      infix ""      suffix ""
     *   UnifiedssotIndividualMc__dlm      prefix ""      infix "ssot"  suffix "Mc"
     *   apj_UnifiedIndividualApx1__dlm    prefix "apj_"  infix ""      suffix "Apx1"
     *
     * The infix is not part of the naming convention: it is the namespace of the source object
     * the ruleset unifies. A default-space ruleset reads ssot__Individual__dlm and carries "ssot"
     * into every name it generates, while a data space that renamed its objects to
     * apj_Individual__dlm has no namespace left to carry and generates names without one. Taking
     * it from the bound name rather than assuming "ssot" is what lets one page serve both.
     */
    private static final Pattern BOUND_NAME = Pattern.compile(
        '(?i)^((?:[A-Za-z0-9]+_)+)?Unified(.*?)Individual(.*?)__dlm$'
    );

    public class DmoSet {
        public String unifiedIndividual;
        public String individualLink;
        public String unifiedEmail;
        public String emailLink;
        public String unifiedPhone;
        public String phoneLink;
        public String unifiedAddress;
        public String addressLink;
        /**
         * Leading part of this ruleset's segment membership tables, which carry an org-specific
         * numeric suffix (ssotIndividualMc_Unified_SMH_178239085__dlm). The full name is read
         * from MarketSegment.SegmentMembershipTable rather than guessed.
         */
        public String segmentTablePrefix;
        /**
         * Ruleset suffix carried by the DMO names ("Mc", "Poc1"), blank for the default naming.
         * IdentityResolution.Suffix holds the same token, which is how a profile is traced back
         * to the ruleset that built it.
         */
        public String rulesetSuffix;
        /**
         * Data space this profile lives in. ConnectApi SQL is scoped to one data space and cannot
         * see across the boundary even when given a fully prefixed name, so every query has to
         * name it. SOQL against __dlm is not scoped and ignores this.
         */
        public String dataSpace;
        /** Prefix this data space stamps onto its object names, blank in the default space. */
        public String prefix;

        public String srcIndividual { get { return shared(SRC_INDIVIDUAL); } }
        public String srcEmail { get { return shared(SRC_EMAIL); } }
        public String srcPhone { get { return shared(SRC_PHONE); } }
        public String srcAddress { get { return shared(SRC_ADDRESS); } }
        public String emailEngagement { get { return shared(EMAIL_ENGAGEMENT); } }
        public String webEngagement { get { return shared(WEB_ENGAGEMENT); } }
        public String bulkEmailMessage { get { return shared(BULK_EMAIL_MESSAGE); } }
        public String salesOrder { get { return shared(SALES_ORDER); } }

        /**
         * Objects that are not built by identity resolution and so keep one name per data space,
         * shared by every ruleset in it. Only the data space prefix can move them.
         */
        private String shared(String standardName) {
            return resolveInSpace(standardName, prefix, dataSpace);
        }
    }

    private static final Map<String, DmoSet> CACHE = new Map<String, DmoSet>();

    /**
     * @param unifiedDmo API name of the Unified Individual DMO (e.g. UnifiedIndividual__dlm,
     *                   UnifiedssotIndividualMc__dlm, apj_UnifiedssotIndividualPoc1__dlm)
     */
    public static DmoSet resolve(String unifiedDmo) {
        String key = String.isBlank(unifiedDmo) ? DEFAULT_UNIFIED : unifiedDmo.trim();
        if (CACHE.containsKey(key)) {
            return CACHE.get(key);
        }

        DmoSet result = new DmoSet();
        result.unifiedIndividual = key;

        String prefix = '';
        String infix = '';
        String suffix = '';
        Matcher parts = BOUND_NAME.matcher(key);
        if (parts.matches()) {
            prefix = parts.group(1) == null ? '' : parts.group(1);
            infix = parts.group(2) == null ? '' : parts.group(2);
            suffix = parts.group(3) == null ? '' : parts.group(3);
        }

        result.prefix = prefix;
        result.rulesetSuffix = suffix;
        result.dataSpace = spaceFor(suffix, key);
        result.segmentTablePrefix = infix + 'Individual' + suffix + '_Unified_SM';

        /*
         * Unified objects are named the same way under every convention seen so far. Link objects
         * are not: the first ruleset in a space names them <Entity>IdentityLink, while a suffixed
         * one names them UnifiedLink<Entity><Suffix>. Which of the two a ruleset uses is settled
         * once, on the individual, because a ruleset does not mix the forms across its objects.
         */
        Boolean firstRuleset = String.isBlank(infix) && String.isBlank(suffix);
        String chosen = pickName(
            firstRuleset
                ? new List<String>{ identityLink(prefix, 'Individual'), unifiedLink(prefix, infix, suffix, 'Individual') }
                : new List<String>{ unifiedLink(prefix, infix, suffix, 'Individual'), identityLink(prefix, 'Individual') },
            prefix,
            result.dataSpace
        );
        Boolean identityLinkForm = chosen.endsWithIgnoreCase('IdentityLink__dlm');

        for (String entity : ENTITIES) {
            apply(
                result,
                entity,
                prefix + 'Unified' + infix + entity + suffix + '__dlm',
                identityLinkForm
                    ? identityLink(prefix, entity)
                    : unifiedLink(prefix, infix, suffix, entity)
            );
        }

        CACHE.put(key, result);
        return result;
    }

    private static String identityLink(String prefix, String entity) {
        return prefix + entity + 'IdentityLink__dlm';
    }

    private static String unifiedLink(String prefix, String infix, String suffix, String entity) {
        return prefix + 'UnifiedLink' + infix + entity + suffix + '__dlm';
    }

    private static final List<String> ENTITIES = new List<String>{
        'Individual',
        'ContactPointEmail',
        'ContactPointPhone',
        'ContactPointAddress'
    };

    private static void apply(DmoSet result, String entity, String unified, String link) {
        if (entity == 'Individual') {
            result.individualLink = link;
        } else if (entity == 'ContactPointEmail') {
            result.unifiedEmail = unified;
            result.emailLink = link;
        } else if (entity == 'ContactPointPhone') {
            result.unifiedPhone = unified;
            result.phoneLink = link;
        } else {
            result.unifiedAddress = unified;
            result.addressLink = link;
        }
    }

    /**
     * First spelling the space actually has. In the default space the leading candidate is the
     * only one the platform generates, so it is taken without asking. Elsewhere the guess is
     * checked, and if none of the candidates exist the leading one is still returned: a name that
     * turns up empty reads better than a null that has to be guarded at every call site.
     */
    private static String pickName(List<String> options, String prefix, String dataSpace) {
        if (String.isBlank(prefix)) {
            return options[0];
        }
        for (String option : options) {
            if (existsInSpace(option, dataSpace)) {
                return option;
            }
        }
        return options[0];
    }

    // ---------------------------------------------------------------- data space

    @TestVisible
    private static Map<String, List<String>> spacesBySuffix;

    /**
     * Data space of the ruleset that produced this profile.
     *
     * Nothing here decides which space is "the default" one, because nothing needs to: a profile
     * belongs to the space its ruleset was defined in, and that is read from the ruleset itself.
     * When it cannot be read the answer is blank rather than a guess, and the query then goes out
     * without naming a space so the platform applies its own.
     *
     * A suffix alone is not always enough to identify the ruleset. Two data spaces can each hold
     * a ruleset with the same suffix, and every space can hold an unsuffixed standard one, so a
     * suffix can point at several spaces. The bound DMO settles it: it exists in exactly one of
     * them, and asking is a single metadata lookup.
     */
    @TestVisible
    private static String spaceFor(String rulesetSuffix, String boundDmo) {
        if (spacesBySuffix == null) {
            spacesBySuffix = loadSpaces();
        }

        List<String> spaces = spacesBySuffix.get(
            String.isBlank(rulesetSuffix) ? '' : rulesetSuffix.toLowerCase()
        );
        if (spaces == null || spaces.isEmpty()) {
            return null;
        }
        if (spaces.size() == 1) {
            return spaces[0];
        }

        for (String space : spaces) {
            if (existsInSpace(boundDmo, space)) {
                return space;
            }
        }
        return null;
    }

    private static Map<String, List<String>> loadSpaces() {
        Map<String, List<String>> bySuffix = new Map<String, List<String>>();
        try {
            Map<Id, String> names = new Map<Id, String>();
            for (DataSpace space : [SELECT Id, DataSpaceApiName FROM DataSpace LIMIT 200]) {
                names.put(space.Id, space.DataSpaceApiName);
            }
            for (IdentityResolution ruleset : [
                SELECT Suffix, DataSpaceId
                FROM IdentityResolution
                LIMIT 200
            ]) {
                String space = names.get(ruleset.DataSpaceId);
                if (String.isBlank(space)) {
                    continue;
                }
                String key = ruleset.Suffix == null ? '' : ruleset.Suffix.toLowerCase();
                if (!bySuffix.containsKey(key)) {
                    bySuffix.put(key, new List<String>());
                }
                if (!bySuffix.get(key).contains(space)) {
                    bySuffix.get(key).add(space);
                }
            }
        } catch (Exception e) {
            // Without the rulesets every query still runs, just wherever the platform puts it.
        }
        return bySuffix;
    }

    // ---------------------------------------------------------------- querying

    /**
     * Runs Data Cloud SQL against a data space. ConnectApi SQL is scoped to one space and returns
     * NOT_FOUND for an object in another, even when given that object's full prefixed name, so
     * the space has to be named whenever it is known. Naming it is always safe, including for the
     * default space; passing nothing is what leaves the choice to the platform.
     */
    public static ConnectApi.CdpQueryOutputV2 runQuery(
        ConnectApi.CdpQueryInput input,
        String dataSpace
    ) {
        if (String.isBlank(dataSpace)) {
            return ConnectApi.CdpQuery.queryAnsiSqlV2(input);
        }
        return ConnectApi.CdpQuery.queryAnsiSqlV2(input, dataSpace);
    }

    // ---------------------------------------------------------------- segment membership

    @TestVisible
    private static Map<String, Set<String>> objectsBySpace = new Map<String, Set<String>>();

    private static final Pattern CATALOGUE_NAME = Pattern.compile('name=([A-Za-z0-9_]+__dlm)');

    /** Every data model object a space holds, as the metadata service reports them. */
    @TestVisible
    private static Set<String> objectsIn(String dataSpace) {
        String key = String.isBlank(dataSpace) ? '' : dataSpace;
        if (objectsBySpace.containsKey(key)) {
            return objectsBySpace.get(key);
        }

        Set<String> names = new Set<String>();
        try {
            ConnectApi.CdpQueryMetadataOutput output = ConnectApi.CdpQuery.getAllMetadata(
                'DataModelObject',
                null,
                null,
                dataSpace
            );
            if (output != null && output.metadata != null) {
                // Each entry is read on its own: converting the whole reply at once truncates it.
                for (Object entry : output.metadata) {
                    Matcher found = CATALOGUE_NAME.matcher(String.valueOf(entry));
                    if (found.find()) {
                        names.add(found.group(1));
                    }
                }
            }
        } catch (Exception e) {
            // No catalogue means the caller falls back to whatever else it can find.
        }

        objectsBySpace.put(key, names);
        return names;
    }

    /**
     * Segment membership tables for one ruleset, current membership ahead of history.
     *
     * Each ruleset gets a pair: <ruleset>_Unified_SM_<id> holding who is in each segment now, and
     * <ruleset>_Unified_SMH_<id> accumulating every change. The current table is the one worth
     * reading — measured against one ruleset in Asset Org 2 it covered twelve segments and eleven
     * members where the history table showed ten and four, because history keeps repeating the
     * same few members rather than recording the rest.
     *
     * They have to be discovered rather than constructed. The two ids differ from each other
     * (..._SM_1779366683577 against ..._SMH_1779366689783), they are assigned per org, and the
     * platform truncates the name once it grows too long, which cuts the id short. The ruleset's
     * own prefix is what separates its tables from another ruleset's, from segments built on the
     * source object rather than the unified one, and from other entities entirely.
     */
    public static List<String> segmentTables(
        String segmentPrefix,
        String spacePrefix,
        String dataSpace
    ) {
        List<String> current = new List<String>();
        List<String> history = new List<String>();
        if (String.isBlank(segmentPrefix)) {
            return current;
        }

        // A renamed space may or may not stamp its prefix on these; both are allowed for.
        List<String> stems = new List<String>{ segmentPrefix };
        if (String.isNotBlank(spacePrefix)) {
            stems.add(spacePrefix + segmentPrefix);
        }

        for (String name : objectsIn(dataSpace)) {
            for (String stem : stems) {
                if (name.startsWithIgnoreCase(stem + '_')) {
                    current.add(name);
                    break;
                }
                if (name.startsWithIgnoreCase(stem + 'H_')) {
                    history.add(name);
                    break;
                }
            }
        }

        current.sort();
        history.sort();
        return current.isEmpty() ? history : current;
    }

    // ---------------------------------------------------------------- field naming

    @TestVisible
    private static Map<String, Boolean> namespacedFields = new Map<String, Boolean>();

    private static final Pattern QUERIED_OBJECT = Pattern.compile('(?is)\\bFROM\\s+([A-Za-z0-9_]+)');

    /**
     * Whether an object spells its fields with the ssot__ namespace.
     *
     * A data space that renames its objects renames their fields to match: apj_Individual__dlm
     * holds Id__c and FirstName__c where ssot__Individual__dlm holds ssot__Id__c and
     * ssot__FirstName__c. The namespace cannot be inferred from the object name, because the
     * standard ruleset's UnifiedIndividual__dlm carries no prefix of its own yet still uses
     * namespaced fields, so the object is asked directly. A describe is not a callout and the
     * platform caches it, which measured at 382ms cold and 4ms warm.
     *
     * An object that cannot be described is treated as namespaced, leaving the standard spelling
     * in place rather than rewriting a query on a guess.
     */
    public static Boolean usesFieldNamespace(String dmoApiName) {
        if (String.isBlank(dmoApiName)) {
            return true;
        }
        if (namespacedFields.containsKey(dmoApiName)) {
            return namespacedFields.get(dmoApiName);
        }

        Boolean namespaced = true;
        Set<String> held = fieldsOf(dmoApiName);
        if (!held.isEmpty()) {
            namespaced = false;
            for (String field : held) {
                if (field.startsWith('ssot__')) {
                    namespaced = true;
                    break;
                }
            }
        }

        namespacedFields.put(dmoApiName, namespaced);
        return namespaced;
    }

    @TestVisible
    private static Map<String, Set<String>> fieldsByObject = new Map<String, Set<String>>();

    /** Every field an object holds, lowercased. Empty when the object cannot be described. */
    private static Set<String> fieldsOf(String dmoApiName) {
        if (fieldsByObject.containsKey(dmoApiName)) {
            return fieldsByObject.get(dmoApiName);
        }

        Set<String> held = new Set<String>();
        try {
            held.addAll(
                Schema.describeSObjects(new List<String>{ dmoApiName })[0].fields.getMap().keySet()
            );
        } catch (Exception e) {
            // Object not visible here; an empty set leaves every caller to its own fallback.
        }

        fieldsByObject.put(dmoApiName, held);
        return held;
    }

    /**
     * Those of these standard field names that the object actually holds, still in the standard
     * spelling so callers read results back under the name they asked for.
     *
     * Orgs map different subsets of a DMO, and a column the org has not mapped is fatal in a
     * WHERE clause: dropping unknown columns from a SELECT after the fact cannot rescue a
     * predicate that names one. Asking the object first also spares the round trips that dropping
     * them one at a time would cost.
     *
     * Every name is returned when the object cannot be described, which leaves the behaviour as
     * it was before this check existed.
     */
    public static List<String> presentFields(String dmoApiName, List<String> standardNames) {
        Set<String> held = fieldsOf(dmoApiName);
        if (held.isEmpty() || standardNames == null) {
            return standardNames;
        }

        Boolean namespaced = usesFieldNamespace(dmoApiName);
        List<String> present = new List<String>();
        for (String name : standardNames) {
            if (String.isBlank(name)) {
                continue;
            }
            String spelled = namespaced ? name : name.replace('ssot__', '');
            if (held.contains(spelled.toLowerCase())) {
                present.add(name);
            }
        }
        return present;
    }

    /**
     * A query written in the standard spelling, respelled for the object it reads from.
     *
     * The field names are written out longhand throughout the controllers, which reads far better
     * than assembling every one of them from parts. Correcting the spelling once, here, keeps that
     * readability and confines the difference between data spaces to a single place. The object is
     * taken from the query's own FROM clause, so nothing has to be threaded through the callers.
     */
    public static String localise(String query) {
        if (String.isBlank(query) || !query.contains('ssot__')) {
            return query;
        }
        Matcher queried = QUERIED_OBJECT.matcher(query);
        if (!queried.find() || usesFieldNamespace(queried.group(1))) {
            return query;
        }
        return query.replace('ssot__', '');
    }

    /** The standard spelling of each name, respelled for one object. */
    public static List<String> localise(List<String> names, String dmoApiName) {
        if (names == null || names.isEmpty() || usesFieldNamespace(dmoApiName)) {
            return names;
        }
        List<String> respelled = new List<String>();
        for (String name : names) {
            respelled.add(name == null ? null : name.replace('ssot__', ''));
        }
        return respelled;
    }

    /**
     * A row readable under the standard spelling whichever spelling it came back in.
     *
     * Adding the namespaced key alongside the bare one, rather than renaming, means a row is
     * never made unreadable by this: both spellings work, so the reading code stays written the
     * one way.
     */
    public static Map<String, Object> withStandardNames(Map<String, Object> row) {
        if (row == null || row.isEmpty()) {
            return row;
        }
        Map<String, Object> readable = new Map<String, Object>(row);
        for (String key : row.keySet()) {
            if (key != null && !key.startsWith('ssot__') && !readable.containsKey('ssot__' + key)) {
                readable.put('ssot__' + key, row.get(key));
            }
        }
        return readable;
    }

    /** A field read by its standard name, falling back to the space's own spelling. */
    public static Object value(SObject row, String field) {
        if (row == null || String.isBlank(field)) {
            return null;
        }
        try {
            return row.get(field);
        } catch (Exception e) {
            // Not on this object under that name; the other spelling is tried below.
        }
        if (field.startsWith('ssot__')) {
            try {
                return row.get(field.substring(6));
            } catch (Exception e) {
                return null;
            }
        }
        return null;
    }

    /** Object a query reads from, or blank when the query names none. */
    public static String queriedObject(String query) {
        if (String.isBlank(query)) {
            return '';
        }
        Matcher queried = QUERIED_OBJECT.matcher(query);
        return queried.find() ? queried.group(1) : '';
    }

    // ---------------------------------------------------------------- name resolution

    @TestVisible
    private static Map<String, String> resolvedNames = new Map<String, String>();

    /**
     * Picks the spelling of a standard object that this data space actually has. In the default
     * space the standard name is the only candidate and is returned without asking the platform,
     * so the common org pays nothing. A prefixed space is asked once per name per transaction.
     */
    @TestVisible
    private static String resolveInSpace(String standardName, String prefix, String dataSpace) {
        if (String.isBlank(prefix)) {
            return standardName;
        }

        String cacheKey = dataSpace + '|' + prefix + '|' + standardName;
        if (resolvedNames.containsKey(cacheKey)) {
            return resolvedNames.get(cacheKey);
        }

        String found = null;
        for (String candidate : candidates(standardName, prefix)) {
            if (existsInSpace(candidate, dataSpace)) {
                found = candidate;
                break;
            }
        }

        resolvedNames.put(cacheKey, found);
        return found;
    }

    /**
     * A prefixed space may drop the ssot__ namespace in favour of its own prefix
     * (ssot__Individual__dlm becoming apj_Individual__dlm) or keep both. Both spellings are
     * offered, then the unprefixed original in case the object is shared rather than copied.
     */
    @TestVisible
    private static List<String> candidates(String standardName, String prefix) {
        List<String> options = new List<String>();
        if (standardName.startsWithIgnoreCase('ssot__')) {
            options.add(prefix + standardName.substring('ssot__'.length()));
        }
        options.add(prefix + standardName);
        options.add(standardName);
        return options;
    }

    /** Set by tests so name resolution can be exercised without the metadata service. */
    @TestVisible
    private static Set<String> knownNames;

    /** The same, for tests where which space holds the object is the point. */
    @TestVisible
    private static Map<String, Set<String>> namesBySpace;

    @TestVisible
    private static Boolean existsInSpace(String apiName, String dataSpace) {
        if (namesBySpace != null) {
            Set<String> held = namesBySpace.get(dataSpace);
            return held != null && held.contains(apiName);
        }
        if (knownNames != null) {
            return knownNames.contains(apiName);
        }
        try {
            ConnectApi.CdpQueryMetadataOutput output = ConnectApi.CdpQuery.getAllMetadata(
                'DataModelObject',
                null,
                apiName,
                dataSpace
            );
            return output != null && output.metadata != null && !output.metadata.isEmpty();
        } catch (Exception e) {
            // The service throws rather than returning nothing when the name is unknown.
            return false;
        }
    }
}
