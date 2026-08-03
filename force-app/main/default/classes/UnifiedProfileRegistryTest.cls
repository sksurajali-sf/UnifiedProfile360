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
}
