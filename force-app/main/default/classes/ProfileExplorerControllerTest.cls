/**
 * A test sees no Data Cloud rows, so the searches here return nothing and what is checked is
 * everything around them: the pickers, the guard rails that stop a search reaching a query, and
 * the mapping from returned rows to the result list. Nothing asserts that the org holds data,
 * which is what lets these run in any org the package is installed into. Searching against real
 * profiles is covered by scripts/apex/validateSearch.apex.
 */
@IsTest
private class ProfileExplorerControllerTest {
    private static final String UNIFIED_DMO = 'UnifiedIndividual__dlm';

    @IsTest
    static void dataSpacesAreListed() {
        for (ProfileExplorerController.DataSpaceOption s : ProfileExplorerController.getDataSpaces()) {
            Assert.isNotNull(s.apiName);
            Assert.isNotNull(s.label);
        }
    }

    @IsTest
    static void profileDmosComeFromCustomMetadata() {
        Set<String> apiNames = new Set<String>();
        for (ProfileExplorerController.DmoOption d : ProfileExplorerController.getProfileDmos('default')) {
            apiNames.add(d.apiName);
        }

        Assert.isTrue(
            apiNames.contains(UNIFIED_DMO),
            'The standard Unified Individual ships registered for the default data space'
        );
    }

    @IsTest
    static void aBlankDataSpaceMeansTheDefaultOne() {
        Assert.areEqual(
            ProfileExplorerController.getProfileDmos('default').size(),
            ProfileExplorerController.getProfileDmos(null).size()
        );
        Assert.areEqual(0, ProfileExplorerController.getProfileDmos('no_such_space').size());
    }

    @IsTest
    static void attributesAreGroupedAndKeyed() {
        // In an org without the objects mapped the list is empty; whatever is offered has to be
        // addressed as DMO|FIELD, which is what tells the search where to look.
        for (ProfileExplorerController.AttributeOption a : ProfileExplorerController.getAttributes(UNIFIED_DMO)) {
            Assert.isTrue(a.key.contains('|'), 'Keys must encode DMO and field');
            Assert.isTrue(
                a.groupLabel == 'Attributes' || a.groupLabel == 'Related Attributes',
                'Attributes are grouped as direct or related'
            );
        }
    }

    @IsTest
    static void attributesHandleBlankDmo() {
        Assert.areEqual(0, ProfileExplorerController.getAttributes(null).size());
    }

    @IsTest
    static void searchRequiresObjectAndAttribute() {
        ProfileExplorerController.SearchOutcome outcome = ProfileExplorerController.searchProfiles(null, null, 'Sayan');

        Assert.isTrue(outcome.rows.isEmpty());
        Assert.areEqual('Choose an object and an attribute to search.', outcome.message);
    }

    @IsTest
    static void searchRequiresTwoCharacters() {
        ProfileExplorerController.SearchOutcome outcome = ProfileExplorerController.searchProfiles(
            UNIFIED_DMO,
            UNIFIED_DMO + '|ssot__FirstName__c',
            'a'
        );

        Assert.isTrue(outcome.rows.isEmpty());
        Assert.areEqual('Enter at least two characters to search.', outcome.message);
    }

    @IsTest
    static void searchRejectsMalformedAttributeKey() {
        for (String key : new List<String>{ 'DROP TABLE; --', 'OneHalfOnly', 'a b|c d', UNIFIED_DMO + '|;drop' }) {
            ProfileExplorerController.SearchOutcome outcome = ProfileExplorerController.searchProfiles(
                UNIFIED_DMO,
                key,
                'Sayan'
            );
            Assert.areEqual('That attribute is not searchable.', outcome.message, key + ' must be refused');
        }
    }

    @IsTest
    static void searchingAnAttributeOnTheProfileItself() {
        ProfileExplorerController.SearchOutcome outcome = ProfileExplorerController.searchProfiles(
            UNIFIED_DMO,
            UNIFIED_DMO + '|ssot__FirstName__c',
            'Sayan'
        );

        Assert.areEqual('No profiles matched that search.', outcome.message);
        Assert.isFalse(outcome.truncated);
    }

    @IsTest
    static void searchingAContactPointFansOutToTheProfilesBehindIt() {
        ProfileExplorerController.SearchOutcome outcome = ProfileExplorerController.searchProfiles(
            UNIFIED_DMO,
            'UnifiedContactPointEmail__dlm|ssot__EmailAddress__c',
            'example.com'
        );

        Assert.areEqual('No profiles matched that search.', outcome.message);
    }

    @IsTest
    static void oneProfilePerMatchedValueEvenWhenSeveralRecordsCarryIt() {
        Map<String, String> matched = ProfileExplorerController.matches(
            new List<Map<String, Object>>{
                new Map<String, Object>{ 'ssot__PartyId__c' => 'uid-1', 'ssot__EmailAddress__c' => 'a@example.com' },
                new Map<String, Object>{ 'ssot__PartyId__c' => 'uid-1', 'ssot__EmailAddress__c' => 'b@example.com' },
                new Map<String, Object>{ 'ssot__PartyId__c' => '', 'ssot__EmailAddress__c' => 'c@example.com' }
            },
            'ssot__PartyId__c',
            'ssot__EmailAddress__c'
        );

        Assert.areEqual(1, matched.size(), 'A profile appears once however many of its records matched');
        Assert.areEqual('a@example.com', matched.get('uid-1'), 'The first match is what is shown');
    }

    @IsTest
    static void aResultRowCarriesTheNameAndTheValueThatMatched() {
        Datetime created = Datetime.newInstanceGmt(2026, 6, 25, 12, 0, 0);

        List<ProfileExplorerController.ProfileRow> rows = ProfileExplorerController.profileRows(
            new List<Map<String, Object>>{
                new Map<String, Object>{
                    'ssot__Id__c' => 'uid-1',
                    'ssot__PersonName__c' => 'Ravi Nair',
                    'ssot__CreatedDate__c' => created
                },
                new Map<String, Object>{
                    'ssot__Id__c' => 'uid-2',
                    'ssot__FirstName__c' => 'Divya',
                    'ssot__LastName__c' => 'Rao'
                }
            },
            new Map<String, String>{ 'uid-1' => 'a@example.com' }
        );

        Assert.areEqual(2, rows.size());
        Assert.areEqual('Ravi Nair', rows[0].name);
        Assert.areEqual('a@example.com', rows[0].matchedValue);
        Assert.areEqual(created, rows[0].createdDate);
        Assert.areEqual('Divya Rao', rows[1].name);
        Assert.isNull(rows[1].matchedValue, 'A profile the search did not match on shows no value');
    }

    @IsTest
    static void aNameIsBuiltFromWhicheverPartsTheSourceFilled() {
        Assert.areEqual('Ravi Nair', ProfileExplorerController.displayName('Ravi Nair', 'Ravi', 'Nair'));
        Assert.areEqual('Ravi Nair', ProfileExplorerController.displayName(null, 'Ravi', 'Nair'));
        // Several systems put the whole name in both parts.
        Assert.areEqual('Ravi Nair', ProfileExplorerController.displayName('', 'Ravi Nair', 'Ravi Nair'));
        Assert.areEqual('Ravi', ProfileExplorerController.displayName(null, 'Ravi', ''));
        Assert.isNull(ProfileExplorerController.displayName(null, null, null));
    }

    @IsTest
    static void anObjectThisOrgDoesNotHaveIsSkippedRatherThanFatal() {
        // A ruleset need not have every contact point object, and the picker has to survive that.
        Assert.areEqual(0, ProfileExplorerController.fieldLabels('NotAnObject__dlm').size());
        // Second call comes back off the cache.
        Assert.areEqual(0, ProfileExplorerController.fieldLabels('NotAnObject__dlm').size());
    }
}
