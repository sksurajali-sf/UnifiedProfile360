/**
 * The registry is what makes one page serve every Identity Resolution ruleset: it turns the
 * Unified Individual DMO a page is rendering into the family of unified, link and segment tables
 * that belong to the same ruleset. None of those objects can be created in an Apex test, so what
 * is worth pinning down is the naming itself — the default ruleset, a suffixed one, and the
 * behaviour when the page hands over nothing at all.
 */
@IsTest
private class UnifiedProfileRegistryTest {
    @IsTest
    static void defaultRulesetUsesTheStandardNames() {
        UnifiedProfileRegistry.DmoSet dmo = UnifiedProfileRegistry.resolve('UnifiedIndividual__dlm');

        Assert.areEqual('UnifiedIndividual__dlm', dmo.unifiedIndividual);
        Assert.areEqual('IndividualIdentityLink__dlm', dmo.individualLink);
        Assert.areEqual('UnifiedContactPointEmail__dlm', dmo.unifiedEmail);
        Assert.areEqual('ContactPointEmailIdentityLink__dlm', dmo.emailLink);
        Assert.areEqual('UnifiedContactPointPhone__dlm', dmo.unifiedPhone);
        Assert.areEqual('ContactPointPhoneIdentityLink__dlm', dmo.phoneLink);
        Assert.areEqual('UnifiedContactPointAddress__dlm', dmo.unifiedAddress);
        Assert.areEqual('ContactPointAddressIdentityLink__dlm', dmo.addressLink);
        Assert.areEqual('Individual_Unified_SM', dmo.segmentTablePrefix);
        Assert.areEqual('', dmo.rulesetSuffix, 'The standard ruleset carries no suffix');
    }

    @IsTest
    static void aSuffixedRulesetCarriesItsSuffixThroughEveryName() {
        UnifiedProfileRegistry.DmoSet dmo = UnifiedProfileRegistry.resolve('UnifiedssotIndividualMc__dlm');

        Assert.areEqual('Mc', dmo.rulesetSuffix);
        Assert.areEqual('UnifiedLinkssotIndividualMc__dlm', dmo.individualLink);
        Assert.areEqual('UnifiedssotContactPointEmailMc__dlm', dmo.unifiedEmail);
        Assert.areEqual('UnifiedLinkssotContactPointEmailMc__dlm', dmo.emailLink);
        Assert.areEqual('UnifiedssotContactPointPhoneMc__dlm', dmo.unifiedPhone);
        Assert.areEqual('UnifiedLinkssotContactPointPhoneMc__dlm', dmo.phoneLink);
        Assert.areEqual('UnifiedssotContactPointAddressMc__dlm', dmo.unifiedAddress);
        Assert.areEqual('UnifiedLinkssotContactPointAddressMc__dlm', dmo.addressLink);
        Assert.areEqual('ssotIndividualMc_Unified_SM', dmo.segmentTablePrefix);
    }

    @IsTest
    static void anyNewRulesetResolvesWithoutACodeChange() {
        // A ruleset nobody has seen before still resolves, which is the whole point of deriving
        // the names instead of listing them.
        UnifiedProfileRegistry.DmoSet dmo = UnifiedProfileRegistry.resolve('UnifiedssotIndividualPoc1__dlm');

        Assert.areEqual('Poc1', dmo.rulesetSuffix);
        Assert.areEqual('UnifiedssotContactPointEmailPoc1__dlm', dmo.unifiedEmail);
        Assert.areEqual('ssotIndividualPoc1_Unified_SM', dmo.segmentTablePrefix);
    }

    @IsTest
    static void aPageWithNoObjectNameFallsBackToTheStandardRuleset() {
        for (String missing : new List<String>{ null, '', '   ' }) {
            UnifiedProfileRegistry.DmoSet dmo = UnifiedProfileRegistry.resolve(missing);
            Assert.areEqual('UnifiedIndividual__dlm', dmo.unifiedIndividual);
            Assert.areEqual('IndividualIdentityLink__dlm', dmo.individualLink);
        }
    }

    @IsTest
    static void surroundingSpaceAndCasingDoNotChangeTheAnswer() {
        Assert.areEqual(
            'UnifiedssotContactPointEmailMc__dlm',
            UnifiedProfileRegistry.resolve('  UnifiedssotIndividualMc__dlm  ').unifiedEmail,
            'Object names arriving from the URL can carry padding'
        );
        Assert.areEqual(
            'Mc',
            UnifiedProfileRegistry.resolve('unifiedssotindividualMc__dlm').rulesetSuffix,
            'The DMO name is matched without regard to case'
        );
    }

    @IsTest
    static void repeatedLookupsReturnTheSameResolvedSet() {
        // Every panel on the page resolves the same DMO, so the answer is cached for the request.
        UnifiedProfileRegistry.DmoSet first = UnifiedProfileRegistry.resolve('UnifiedssotIndividualMc__dlm');
        UnifiedProfileRegistry.DmoSet second = UnifiedProfileRegistry.resolve('UnifiedssotIndividualMc__dlm');

        Assert.isTrue(first === second, 'The resolved set is reused rather than rebuilt');
    }

    @IsTest
    static void sourceObjectNamesAreTheStandardOnes() {
        // These are the same in every org and every ruleset; the unified side is what varies.
        Assert.areEqual('ssot__Individual__dlm', UnifiedProfileRegistry.SRC_INDIVIDUAL);
        Assert.areEqual('ssot__ContactPointEmail__dlm', UnifiedProfileRegistry.SRC_EMAIL);
        Assert.areEqual('ssot__ContactPointPhone__dlm', UnifiedProfileRegistry.SRC_PHONE);
        Assert.areEqual('ssot__ContactPointAddress__dlm', UnifiedProfileRegistry.SRC_ADDRESS);
        Assert.areEqual('ssot__EmailEngagement__dlm', UnifiedProfileRegistry.EMAIL_ENGAGEMENT);
        Assert.areEqual('ssot__WebsiteEngagement__dlm', UnifiedProfileRegistry.WEB_ENGAGEMENT);
        Assert.areEqual('ssot__BulkEmailMessage__dlm', UnifiedProfileRegistry.BULK_EMAIL_MESSAGE);
        Assert.areEqual('ssot__SalesOrder__dlm', UnifiedProfileRegistry.SALES_ORDER);
    }

    @IsTest
    static void theDefaultSpaceKeepsStandardNamesWithoutAskingThePlatform() {
        // knownNames is left null, so any name resolution that reached the metadata service
        // would have to make a call. The default space must not need one.
        UnifiedProfileRegistry.DmoSet dmo = UnifiedProfileRegistry.resolve('UnifiedIndividual__dlm');

        Assert.areEqual('', dmo.prefix, 'The default space stamps no prefix');
        Assert.areEqual('ssot__Individual__dlm', dmo.srcIndividual);
        Assert.areEqual('ssot__EmailEngagement__dlm', dmo.emailEngagement);
        Assert.areEqual('ssot__WebsiteEngagement__dlm', dmo.webEngagement);
        Assert.areEqual('ssot__SalesOrder__dlm', dmo.salesOrder);
    }

    @IsTest
    static void aDataSpacePrefixIsReadOffTheBoundNameAndCarriedThrough() {
        // A data space renames everything it holds. The prefix exists nowhere but in the names,
        // so it is taken from the one name the page already knows.
        UnifiedProfileRegistry.knownNames = new Set<String>();

        UnifiedProfileRegistry.DmoSet dmo = UnifiedProfileRegistry.resolve(
            'apj_UnifiedssotIndividualMc__dlm'
        );

        Assert.areEqual('apj_', dmo.prefix);
        Assert.areEqual('Mc', dmo.rulesetSuffix, 'The ruleset suffix survives the prefix');
        Assert.areEqual('apj_UnifiedLinkssotIndividualMc__dlm', dmo.individualLink);
        Assert.areEqual('apj_UnifiedssotContactPointEmailMc__dlm', dmo.unifiedEmail);
        Assert.areEqual('apj_UnifiedLinkssotContactPointAddressMc__dlm', dmo.addressLink);
    }

    @IsTest
    static void aSpaceThatRenamedItsSourceObjectsGeneratesNamesWithoutTheNamespace() {
        /*
         * Taken from a real ruleset in the Apex_Junior data space. Because its source object is
         * apj_Individual__dlm rather than ssot__Individual__dlm, there is no namespace to carry
         * into the generated names, so nothing here contains "ssot" even though the equivalent
         * ruleset in the default space would.
         */
        UnifiedProfileRegistry.knownNames = new Set<String>{
            'apj_UnifiedLinkIndividualApx1__dlm',
            'apj_UnifiedLinkContactPointEmailApx1__dlm',
            'apj_UnifiedLinkContactPointPhoneApx1__dlm',
            'apj_UnifiedLinkContactPointAddressApx1__dlm'
        };

        UnifiedProfileRegistry.DmoSet dmo = UnifiedProfileRegistry.resolve(
            'apj_UnifiedIndividualApx1__dlm'
        );

        Assert.areEqual('apj_', dmo.prefix);
        Assert.areEqual('Apx1', dmo.rulesetSuffix);
        Assert.areEqual('apj_UnifiedLinkIndividualApx1__dlm', dmo.individualLink);
        Assert.areEqual('apj_UnifiedContactPointEmailApx1__dlm', dmo.unifiedEmail);
        Assert.areEqual('apj_UnifiedLinkContactPointEmailApx1__dlm', dmo.emailLink);
        Assert.areEqual('apj_UnifiedContactPointPhoneApx1__dlm', dmo.unifiedPhone);
        Assert.areEqual('apj_UnifiedContactPointAddressApx1__dlm', dmo.unifiedAddress);
        Assert.areEqual('apj_UnifiedLinkContactPointAddressApx1__dlm', dmo.addressLink);
        Assert.areEqual('IndividualApx1_Unified_SM', dmo.segmentTablePrefix);
    }

    @IsTest
    static void twoRulesetsInOneRenamedSpaceStayApart() {
        UnifiedProfileRegistry.knownNames = new Set<String>{
            'apj_UnifiedLinkIndividualApx1__dlm',
            'apj_UnifiedLinkIndividualApx2__dlm'
        };

        Assert.areEqual(
            'apj_UnifiedLinkIndividualApx1__dlm',
            UnifiedProfileRegistry.resolve('apj_UnifiedIndividualApx1__dlm').individualLink
        );
        Assert.areEqual(
            'apj_UnifiedLinkIndividualApx2__dlm',
            UnifiedProfileRegistry.resolve('apj_UnifiedIndividualApx2__dlm').individualLink
        );
    }

    /*
     * Field naming is the second half of the same story as object naming: a data space that
     * renames its objects renames their fields to match. These use the field cache directly so
     * the behaviour is pinned down without depending on what the running org happens to hold.
     */
    @IsTest
    static void aQueryIsLeftAloneWhenTheObjectUsesTheStandardNamespace() {
        UnifiedProfileRegistry.fieldsByObject = new Map<String, Set<String>>{
            'ssot__Individual__dlm' => new Set<String>{ 'ssot__id__c', 'ssot__firstname__c' }
        };

        String soql = 'SELECT ssot__Id__c FROM ssot__Individual__dlm WHERE ssot__Id__c = :uid';
        Assert.areEqual(soql, UnifiedProfileRegistry.localise(soql));
    }

    @IsTest
    static void aQueryIsRespelledForAnObjectThatDroppedTheNamespace() {
        UnifiedProfileRegistry.fieldsByObject = new Map<String, Set<String>>{
            'apj_Individual__dlm' => new Set<String>{ 'id__c', 'firstname__c' }
        };

        Assert.areEqual(
            'SELECT Id__c, FirstName__c FROM apj_Individual__dlm WHERE Id__c = :uid',
            UnifiedProfileRegistry.localise(
                'SELECT ssot__Id__c, ssot__FirstName__c FROM apj_Individual__dlm WHERE ssot__Id__c = :uid'
            )
        );
    }

    @IsTest
    static void aRowIsReadableUnderTheStandardNameWhicheverSpellingItArrivedIn() {
        Map<String, Object> row = UnifiedProfileRegistry.withStandardNames(
            new Map<String, Object>{ 'Id__c' => 'abc', 'ssot__LastName__c' => 'Hoeger' }
        );

        Assert.areEqual('abc', row.get('ssot__Id__c'), 'The standard name reaches the bare value');
        Assert.areEqual('abc', row.get('Id__c'), 'The original name still works');
        Assert.areEqual('Hoeger', row.get('ssot__LastName__c'));
    }

    @IsTest
    static void onlyTheColumnsAnOrgMappedAreAskedFor() {
        // apj_SalesOrder__dlm in Asset Org 2 maps neither the grand total nor the bill-to contact.
        UnifiedProfileRegistry.fieldsByObject = new Map<String, Set<String>>{
            'apj_SalesOrder__dlm' => new Set<String>{
                'id__c',
                'soldtocustomerid__c',
                'totalproductamount__c'
            }
        };

        List<String> present = UnifiedProfileRegistry.presentFields(
            'apj_SalesOrder__dlm',
            new List<String>{
                'ssot__Id__c',
                'ssot__GrandTotalAmount__c',
                'ssot__SoldToCustomerId__c',
                'ssot__BillToContactId__c'
            }
        );

        Assert.areEqual(
            new List<String>{ 'ssot__Id__c', 'ssot__SoldToCustomerId__c' },
            present,
            'Unmapped columns are dropped and the rest keep the name the caller reads back by'
        );
    }

    @IsTest
    static void everyColumnIsKeptWhenTheObjectCannotBeDescribed() {
        UnifiedProfileRegistry.fieldsByObject = new Map<String, Set<String>>{
            'Mystery__dlm' => new Set<String>()
        };

        List<String> asked = new List<String>{ 'ssot__Id__c', 'ssot__GrandTotalAmount__c' };
        Assert.areEqual(asked, UnifiedProfileRegistry.presentFields('Mystery__dlm', asked));
    }

    @IsTest
    static void aPrefixMadeOfSeveralPartsIsStillRecognised() {
        // Nothing constrains a data space prefix to one word.
        UnifiedProfileRegistry.knownNames = new Set<String>();

        UnifiedProfileRegistry.DmoSet dmo = UnifiedProfileRegistry.resolve(
            'apac_retail_UnifiedIndividualApx1__dlm'
        );

        Assert.areEqual('apac_retail_', dmo.prefix);
        Assert.areEqual('Apx1', dmo.rulesetSuffix);
        Assert.areEqual('apac_retail_UnifiedLinkIndividualApx1__dlm', dmo.individualLink);
        Assert.areEqual('apac_retail_UnifiedContactPointEmailApx1__dlm', dmo.unifiedEmail);
    }

    @IsTest
    static void anUnsuffixedRulesetInARenamedSpaceUsesWhicheverLinkFormExists() {
        // The first ruleset in a space names its links <Entity>IdentityLink. A space that renamed
        // its objects may still do that, so the form is confirmed rather than assumed.
        UnifiedProfileRegistry.knownNames = new Set<String>{ 'apj_UnifiedLinkIndividual__dlm' };

        UnifiedProfileRegistry.DmoSet dmo = UnifiedProfileRegistry.resolve('apj_UnifiedIndividual__dlm');

        Assert.areEqual('', dmo.rulesetSuffix);
        Assert.areEqual('apj_UnifiedLinkIndividual__dlm', dmo.individualLink);
        Assert.areEqual(
            'apj_UnifiedLinkContactPointEmail__dlm',
            dmo.emailLink,
            'The form settled on the individual applies to the contact points too'
        );
    }

    @IsTest
    static void theNamespaceCarriedIntoTheNamesIsWhateverTheBoundObjectShows() {
        // Same suffix, two spaces, one of which kept the ssot namespace on its source objects.
        UnifiedProfileRegistry.knownNames = new Set<String>();

        Assert.areEqual(
            'UnifiedssotContactPointEmailApx1__dlm',
            UnifiedProfileRegistry.resolve('UnifiedssotIndividualApx1__dlm').unifiedEmail
        );
        Assert.areEqual(
            'apj_UnifiedContactPointEmailApx1__dlm',
            UnifiedProfileRegistry.resolve('apj_UnifiedIndividualApx1__dlm').unifiedEmail
        );
    }

    @IsTest
    static void aPrefixedSpaceUsesWhicheverSpellingTheOrgActuallyHas() {
        // ssot__Individual__dlm becomes apj_Individual__dlm in one org and keeps the namespace
        // in another. Both are offered and the one that exists wins.
        UnifiedProfileRegistry.knownNames = new Set<String>{
            'apj_Individual__dlm',
            'apj_ssot__SalesOrder__dlm',
            'ssot__EmailEngagement__dlm'
        };
        UnifiedProfileRegistry.resolvedNames.clear();

        UnifiedProfileRegistry.DmoSet dmo = UnifiedProfileRegistry.resolve(
            'apj_UnifiedssotIndividualMc__dlm'
        );

        Assert.areEqual('apj_Individual__dlm', dmo.srcIndividual, 'The prefix replaces ssot__');
        Assert.areEqual('apj_ssot__SalesOrder__dlm', dmo.salesOrder, 'The prefix can also lead it');
        Assert.areEqual(
            'ssot__EmailEngagement__dlm',
            dmo.emailEngagement,
            'An object the space shares rather than copies keeps its own name'
        );
    }

    @IsTest
    static void anObjectMissingFromTheSpaceResolvesToNothingRatherThanAGuess() {
        // Naming a table the space does not have is what produced "table does not exist" in the
        // field. Returning null lets the panel say so instead.
        UnifiedProfileRegistry.knownNames = new Set<String>{ 'apj_Individual__dlm' };
        UnifiedProfileRegistry.resolvedNames.clear();

        UnifiedProfileRegistry.DmoSet dmo = UnifiedProfileRegistry.resolve(
            'apj_UnifiedssotIndividualPoc1__dlm'
        );

        Assert.areEqual('apj_Individual__dlm', dmo.srcIndividual);
        Assert.isNull(dmo.webEngagement, 'Nothing is invented for an object that is not there');
        Assert.isNull(dmo.salesOrder);
    }

    @IsTest
    static void everySpellingTheSpaceMightUseIsOffered() {
        List<String> options = UnifiedProfileRegistry.candidates('ssot__Individual__dlm', 'apj_');

        Assert.areEqual(
            new List<String>{ 'apj_Individual__dlm', 'apj_ssot__Individual__dlm', 'ssot__Individual__dlm' },
            options
        );
    }

    @IsTest
    static void theSpaceComesFromTheRulesetThatBuiltTheProfile() {
        UnifiedProfileRegistry.spacesBySuffix = new Map<String, List<String>>{
            'mc' => new List<String>{ 'apj' },
            '' => new List<String>{ 'emea' }
        };

        Assert.areEqual(
            'apj',
            UnifiedProfileRegistry.spaceFor('Mc', 'apj_UnifiedssotIndividualMc__dlm'),
            'The suffix is matched without regard to case'
        );
        Assert.areEqual(
            'emea',
            UnifiedProfileRegistry.spaceFor('', 'emea_UnifiedIndividual__dlm'),
            'The standard ruleset is found by its empty suffix'
        );
    }

    @IsTest
    static void anUnknownRulesetNamesNoSpaceRatherThanGuessingOne() {
        // Naming the wrong space is worse than naming none: the query service reads a blank as
        // "wherever this org puts things", which is right, and a wrong name as an object that
        // does not exist.
        UnifiedProfileRegistry.spacesBySuffix = new Map<String, List<String>>{
            'mc' => new List<String>{ 'apj' }
        };

        Assert.isNull(UnifiedProfileRegistry.spaceFor('Unheard_Of', 'UnifiedssotIndividualXx__dlm'));
        Assert.isNull(UnifiedProfileRegistry.spaceFor('', 'UnifiedIndividual__dlm'));
    }

    @IsTest
    static void aSuffixSharedByTwoSpacesIsSettledByTheBoundObject() {
        // Every data space can hold its own standard ruleset, so an empty suffix routinely points
        // at several. The object the page was opened on exists in only one of them.
        UnifiedProfileRegistry.spacesBySuffix = new Map<String, List<String>>{
            '' => new List<String>{ 'emea', 'apj' }
        };
        UnifiedProfileRegistry.namesBySpace = new Map<String, Set<String>>{
            'emea' => new Set<String>{ 'emea_UnifiedIndividual__dlm' },
            'apj' => new Set<String>{ 'apj_UnifiedIndividual__dlm' }
        };

        Assert.areEqual(
            'apj',
            UnifiedProfileRegistry.spaceFor('', 'apj_UnifiedIndividual__dlm'),
            'The space that actually holds the object wins'
        );
    }

    /** The catalogue as Asset Org 2 reports it, standing in for the metadata call. */
    private static void catalogueHolds(Set<String> names) {
        UnifiedProfileRegistry.objectsBySpace.put('', names);
    }

    private static final Set<String> ASSET_ORG_2 = new Set<String>{
        'Individual_Unified_SM_1779366683577__dlm',
        'Individual_Unified_SMH_1779366689783__dlm',
        'ssotIndividualMc_Unified_SM_1782390847__dlm',
        'ssotIndividualMc_Unified_SMH_178239085__dlm',
        'ssotIndividualPoc1_Unified_SM_17823906__dlm',
        'ssotIndividualPoc1_Unified_SMH_1782390__dlm',
        'Individual_SM_1782815121099__dlm',
        'Individual_SMH_1782815127904__dlm',
        'Account_SM_1781519503699__dlm',
        'Account_SMH_1781519509974__dlm'
    };

    @IsTest
    static void currentMembershipIsPreferredToHistory() {
        catalogueHolds(ASSET_ORG_2);

        List<String> tables = UnifiedProfileRegistry.segmentTables(
            'ssotIndividualMc_Unified_SM',
            null,
            null
        );

        Assert.areEqual(
            new List<String>{ 'ssotIndividualMc_Unified_SM_1782390847__dlm' },
            tables,
            'The history table should be left behind while the current one exists.'
        );
    }

    @IsTest
    static void oneRulesetsSegmentsAreNotAnothers() {
        catalogueHolds(ASSET_ORG_2);

        Assert.areEqual(
            new List<String>{ 'ssotIndividualPoc1_Unified_SM_17823906__dlm' },
            UnifiedProfileRegistry.segmentTables('ssotIndividualPoc1_Unified_SM', null, null),
            'A truncated id should not stop a ruleset finding its own table.'
        );
    }

    /**
     * The standard ruleset's prefix is a leading part of nothing else, but segments built on the
     * source object sit one word away from it and have to stay out.
     */
    @IsTest
    static void segmentsOnTheSourceObjectAndOnOtherEntitiesAreLeftOut() {
        catalogueHolds(ASSET_ORG_2);

        Assert.areEqual(
            new List<String>{ 'Individual_Unified_SM_1779366683577__dlm' },
            UnifiedProfileRegistry.segmentTables('Individual_Unified_SM', null, null),
            'Individual_SM_ and Account_SM_ are other things entirely.'
        );
    }

    @IsTest
    static void historyIsReadWhenItIsAllTheOrgHas() {
        catalogueHolds(
            new Set<String>{
                'ssotIndividualMc_Unified_SMH_178239085__dlm',
                'Account_SM_1781519503699__dlm'
            }
        );

        Assert.areEqual(
            new List<String>{ 'ssotIndividualMc_Unified_SMH_178239085__dlm' },
            UnifiedProfileRegistry.segmentTables('ssotIndividualMc_Unified_SM', null, null),
            'A panel showing history beats a panel showing nothing.'
        );
    }

    @IsTest
    static void aRenamedSpaceMayOrMayNotStampItsPrefixOnThem() {
        catalogueHolds(new Set<String>{ 'apj_IndividualApx1_Unified_SM_178239084__dlm' });

        Assert.areEqual(
            new List<String>{ 'apj_IndividualApx1_Unified_SM_178239084__dlm' },
            UnifiedProfileRegistry.segmentTables('IndividualApx1_Unified_SM', 'apj_', null),
            'The space prefix should be tried as well as omitted.'
        );
    }

    @IsTest
    static void aRulesetWithNoSegmentsFindsNoTables() {
        catalogueHolds(ASSET_ORG_2);

        Assert.areEqual(
            0,
            UnifiedProfileRegistry.segmentTables('ssotIndividualOld_Unified_SM', null, null).size()
        );
        Assert.areEqual(0, UnifiedProfileRegistry.segmentTables('', null, null).size());
    }

    @IsTest
    static void aSharedSuffixThatMatchesNoSpaceNamesNone() {
        UnifiedProfileRegistry.spacesBySuffix = new Map<String, List<String>>{
            '' => new List<String>{ 'emea', 'apj' }
        };
        UnifiedProfileRegistry.namesBySpace = new Map<String, Set<String>>{
            'emea' => new Set<String>{ 'emea_UnifiedIndividual__dlm' },
            'apj' => new Set<String>{ 'apj_UnifiedIndividual__dlm' }
        };

        Assert.isNull(UnifiedProfileRegistry.spaceFor('', 'nordics_UnifiedIndividual__dlm'));
    }
}
