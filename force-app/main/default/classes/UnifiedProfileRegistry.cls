/**
 * Resolves the family of Data Cloud DMOs that belong to a single Identity Resolution
 * ruleset, starting from the Unified Individual DMO the record page is rendering.
 *
 * Rulesets follow a predictable naming convention, so suffixes (Mc, Poc1, ...) are
 * derived at runtime rather than hard-coded. That keeps one page/codebase working as
 * new rulesets and data spaces are added.
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
    private static final Pattern RULESET_PATTERN = Pattern.compile('(?i)^UnifiedssotIndividual(.+)__dlm$');

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
    }

    private static final Map<String, DmoSet> CACHE = new Map<String, DmoSet>();

    /**
     * @param unifiedDmo API name of the Unified Individual DMO (e.g. UnifiedIndividual__dlm,
     *                   UnifiedssotIndividualMc__dlm, UnifiedssotIndividualPoc1__dlm)
     */
    public static DmoSet resolve(String unifiedDmo) {
        String key = String.isBlank(unifiedDmo) ? DEFAULT_UNIFIED : unifiedDmo.trim();
        if (CACHE.containsKey(key)) {
            return CACHE.get(key);
        }

        DmoSet result = new DmoSet();
        result.unifiedIndividual = key;

        Matcher m = RULESET_PATTERN.matcher(key);
        if (m.matches()) {
            // Ruleset-scoped DMOs, e.g. suffix "Mc" -> UnifiedssotContactPointEmailMc__dlm
            String suffix = m.group(1);
            result.rulesetSuffix = suffix;
            result.individualLink = 'UnifiedLinkssotIndividual' + suffix + '__dlm';
            result.unifiedEmail = 'UnifiedssotContactPointEmail' + suffix + '__dlm';
            result.emailLink = 'UnifiedLinkssotContactPointEmail' + suffix + '__dlm';
            result.unifiedPhone = 'UnifiedssotContactPointPhone' + suffix + '__dlm';
            result.phoneLink = 'UnifiedLinkssotContactPointPhone' + suffix + '__dlm';
            result.unifiedAddress = 'UnifiedssotContactPointAddress' + suffix + '__dlm';
            result.addressLink = 'UnifiedLinkssotContactPointAddress' + suffix + '__dlm';
            result.segmentTablePrefix = 'ssotIndividual' + suffix + '_Unified_SM';
        } else {
            // Default ruleset naming
            result.rulesetSuffix = '';
            result.individualLink = 'IndividualIdentityLink__dlm';
            result.unifiedEmail = 'UnifiedContactPointEmail__dlm';
            result.emailLink = 'ContactPointEmailIdentityLink__dlm';
            result.unifiedPhone = 'UnifiedContactPointPhone__dlm';
            result.phoneLink = 'ContactPointPhoneIdentityLink__dlm';
            result.unifiedAddress = 'UnifiedContactPointAddress__dlm';
            result.addressLink = 'ContactPointAddressIdentityLink__dlm';
            result.segmentTablePrefix = 'Individual_Unified_SM';
        }

        CACHE.put(key, result);
        return result;
    }
}
