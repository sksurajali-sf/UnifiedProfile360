/**
 * The catalogue comes from a service an Apex test cannot reach, so these cover the reading of
 * what it sends back and the guards around the query it builds. The live path is verified
 * against org data by scripts/apex/probeExplorer.apex.
 */
@IsTest
private class UnifiedDmoExplorerControllerTest {
    /*
     * The catalogue offers every object the data model defines, including ones no data stream
     * feeds. Picking one of those is a normal thing to do and has to read as an empty result
     * rather than as the page breaking.
     */
    @IsTest
    static void anObjectWithNoDataBehindItSaysSoInItsOwnTerms() {
        String said = UnifiedDmoExplorerController.queryFailure(
            'Implementation__dlm',
            'Implementation',
            'CDPErrorCode: OBJECT_NOT_FOUND. Failed to execute query: table "Implementation__dlm" ' +
                'does not exist [TraceId:1289fb27867c8acc]'
        );

        Assert.isTrue(said.contains('Implementation (Implementation__dlm)'), said);
        Assert.isTrue(said.contains('no data behind it'), said);
        Assert.isFalse(said.contains('TraceId'), 'A trace id means nothing to whoever is reading');
    }

    @IsTest
    static void anUnmappedColumnNamesTheColumnAndWhatToDo() {
        String said = UnifiedDmoExplorerController.queryFailure(
            'Individual__dlm',
            'Individual',
            'Failed to execute query: unknown column \'Esta_Eliminado__c\' [TraceId:21129c3ba0701442]'
        );

        Assert.isTrue(said.contains('Esta_Eliminado__c'), said);
        Assert.isTrue(said.contains('Choose different columns'), said);
    }

    @IsTest
    static void anythingElseIsPassedThroughRatherThanGuessedAt() {
        String said = UnifiedDmoExplorerController.queryFailure('X__dlm', 'X', 'Request timed out');

        Assert.isTrue(said.contains('Request timed out'), said);
    }

    /** A rendering of one entity, in the shape the metadata service produces. */
    private static final String SALES_ORDER =
        '{fields=[{name=KQ_BillToContactId__c, displayName=Key Qualifier Bill To Contact, type=STRING, businessType=TEXT}, ' +
        '{name=ssot__OrderNumber__c, displayName=Order Number, type=STRING, businessType=TEXT}, ' +
        '{name=ssot__CreatedDate__c, displayName=Created Date, type=DATE_TIME, businessType=DATE_TIME}], ' +
        'indexes=[], category=Engagement, name=ssot__SalesOrder__dlm, displayName=Sales Order, ' +
        'relationships=[{fromEntity=ssot__SalesOrder__dlm, toEntity=ssot__AccountContact__dlm, ' +
        'fromEntityAttribute=ssot__BillToContactId__c, toEntityAttribute=ssot__Id__c, cardinality=NTOONE}], ' +
        'primaryKeys=[{name=ssot__Id__c, displayName=Sales Order Id, indexOrder=1}], ' +
        'referenceModelEntityDeveloperName=}';

    @IsTest
    static void anEntityIsReadOutOfWhatTheServiceRenders() {
        UnifiedDmoExplorerController.Entity entity = UnifiedDmoExplorerController.parseEntity(SALES_ORDER);

        Assert.areEqual('ssot__SalesOrder__dlm', entity.apiName);
        Assert.areEqual('Sales Order', entity.label, 'The label stops before the next key');
        Assert.areEqual('Engagement', entity.category);
        Assert.areEqual(3, entity.fields.size(), 'Key qualifiers are read here and dropped later');
        Assert.areEqual('Order Number', entity.fields[1].label);
        Assert.areEqual('DATE_TIME', entity.fields[2].type);
        Assert.areEqual(1, entity.relationships.size());
        Assert.areEqual('ssot__AccountContact__dlm', entity.relationships[0].toEntity);
        Assert.areEqual('ssot__BillToContactId__c', entity.relationships[0].fromAttribute);
    }

    @IsTest
    static void aRelationshipReadsTheSameFromEitherEnd() {
        UnifiedDmoExplorerController.Relationship rel = UnifiedDmoExplorerController.parseEntity(SALES_ORDER)
            .relationships[0];

        Assert.areEqual(
            'ssot__AccountContact__dlm',
            UnifiedDmoExplorerController.otherEntity(rel, 'ssot__SalesOrder__dlm')
        );
        Assert.areEqual(
            'ssot__SalesOrder__dlm',
            UnifiedDmoExplorerController.otherEntity(rel, 'ssot__AccountContact__dlm')
        );
        Assert.isNull(
            UnifiedDmoExplorerController.otherEntity(rel, 'ssot__Individual__dlm'),
            'An object that is not part of the relationship gets nothing back'
        );

        Assert.areEqual(
            'ssot__BillToContactId__c',
            UnifiedDmoExplorerController.ownAttribute(rel, 'ssot__SalesOrder__dlm')
        );
        Assert.areEqual(
            'ssot__Id__c',
            UnifiedDmoExplorerController.ownAttribute(rel, 'ssot__AccountContact__dlm')
        );
    }

    @IsTest
    static void nonsenseFromTheServiceIsSkippedRatherThanGuessedAt() {
        Assert.isNull(UnifiedDmoExplorerController.parseEntity(null));
        Assert.isNull(UnifiedDmoExplorerController.parseEntity('{category=Profile}'));
    }

    @IsTest
    static void timestampsAreTurnedIntoSomethingAFormatterReads() {
        UnifiedDmoExplorerController.Field stamp = new UnifiedDmoExplorerController.Field();
        stamp.apiName = 'ssot__CreatedDate__c';
        stamp.type = 'DATE_TIME';

        Assert.areEqual(
            '2026-06-05T08:00:44.857Z',
            UnifiedDmoExplorerController.normalise('2026-06-05 08:00:44.857 UTC', stamp)
        );

        UnifiedDmoExplorerController.Field text = new UnifiedDmoExplorerController.Field();
        text.type = 'STRING';
        Assert.areEqual(
            '2026-06-05 08:00:44.857 UTC',
            UnifiedDmoExplorerController.normalise('2026-06-05 08:00:44.857 UTC', text),
            'A text column keeps whatever it holds'
        );
    }

    @IsTest
    static void idsGoIntoTheQueryQuotedAndEscaped() {
        Assert.areEqual(
            '\'abc\', \'d\\\'ef\'',
            UnifiedDmoExplorerController.quotedList(new List<String>{ 'abc', null, '', 'd\'ef' })
        );
    }

    @IsTest
    static void columnsThatShareALabelAreToldApartByTheirApiName() {
        List<UnifiedDmoExplorerController.Field> fields = new List<UnifiedDmoExplorerController.Field>();
        for (String apiName : new List<String>{
            'ssot__ConsentStatus__c',
            'ssot__ConsentStatusId__c',
            'ssot__OrderNumber__c'
        }) {
            UnifiedDmoExplorerController.Field f = new UnifiedDmoExplorerController.Field();
            f.apiName = apiName;
            f.label = apiName == 'ssot__OrderNumber__c' ? 'Order Number' : 'Consent Status';
            fields.add(f);
        }

        UnifiedDmoExplorerController.distinguishLabels(fields);

        Assert.areEqual('Consent Status (ConsentStatus)', fields[0].label);
        Assert.areEqual('Consent Status (ConsentStatusId)', fields[1].label);
        Assert.areEqual('Order Number', fields[2].label, 'A label of its own is left alone');
    }

    @IsTest
    static void aCategoryReadsAsWords() {
        Assert.areEqual('Segment Membership', UnifiedDmoExplorerController.prettyCategory('Segment_Membership'));
        Assert.isNull(UnifiedDmoExplorerController.prettyCategory(null));
    }

    @IsTest
    static void anEmptyCatalogueLeavesAnEmptyPickerRatherThanAnError() {
        // The metadata service is unreachable from a test, which is the same position a page is in
        // when Data Cloud is down.
        List<UnifiedDmoExplorerController.ObjectOption> options = UnifiedDmoExplorerController.getRelatedObjects(
            'UnifiedIndividual__dlm'
        );

        Assert.areEqual(0, options.size());
    }

    @IsTest
    static void anUnknownObjectIsRefusedBeforeAnySqlIsBuilt() {
        try {
            UnifiedDmoExplorerController.search(
                'qHJ000CrNFq5xUhG0I',
                'UnifiedIndividual__dlm',
                'MadeUp__dlm',
                new List<String>{ 'ssot__Id__c' },
                'ssot__Id__c',
                100
            );
            Assert.fail('An object outside the catalogue should never reach the query service');
        } catch (Exception e) {
            Assert.isInstanceOfType(e, AuraHandledException.class);
        }
    }

    // ------------------------------------------------------------------
    // Driven from a catalogue standing in for the metadata service
    // ------------------------------------------------------------------

    private static final String UNIFIED_DMO = 'UnifiedIndividual__dlm';
    private static final String UNIFIED_ID = '0f4a1c9e8b2d47f3a6c50e19b7d83af2';

    private static UnifiedDmoExplorerController.Field field(String apiName, String label, String type) {
        UnifiedDmoExplorerController.Field f = new UnifiedDmoExplorerController.Field();
        f.apiName = apiName;
        f.label = label;
        f.type = type;
        return f;
    }

    private static UnifiedDmoExplorerController.Relationship relates(String fromEntity, String fromAttribute, String toEntity) {
        UnifiedDmoExplorerController.Relationship r = new UnifiedDmoExplorerController.Relationship();
        r.fromEntity = fromEntity;
        r.fromAttribute = fromAttribute;
        r.toEntity = toEntity;
        r.toAttribute = 'ssot__Id__c';
        return r;
    }

    private static UnifiedDmoExplorerController.Entity entity(
        String apiName,
        String label,
        List<UnifiedDmoExplorerController.Field> fields,
        List<UnifiedDmoExplorerController.Relationship> relationships
    ) {
        UnifiedDmoExplorerController.Entity e = new UnifiedDmoExplorerController.Entity();
        e.apiName = apiName;
        e.label = label;
        e.category = 'Engagement';
        e.fields = fields;
        e.relationships = relationships;
        return e;
    }

    /**
     * Email Engagement names the individual itself; Sales Order reaches it through Account
     * Contact, which is the hop the picker has to follow.
     */
    private static void seedCatalogue() {
        UnifiedDmoExplorerController.cachedCatalogue = new Map<String, UnifiedDmoExplorerController.Entity>{
            'ssot__Individual__dlm' => entity(
                'ssot__Individual__dlm',
                'Individual',
                new List<UnifiedDmoExplorerController.Field>{ field('ssot__Id__c', 'Individual Id', 'STRING') },
                new List<UnifiedDmoExplorerController.Relationship>()
            ),
            'ssot__EmailEngagement__dlm' => entity(
                'ssot__EmailEngagement__dlm',
                'Email Engagement',
                new List<UnifiedDmoExplorerController.Field>{
                    field('KQ_IndividualId__c', 'Key Qualifier', 'STRING'),
                    field('ssot__EngagementDateTm__c', 'Engagement Date Time', 'DATE_TIME'),
                    field('ssot__IndividualId__c', 'Individual Id', 'STRING')
                },
                new List<UnifiedDmoExplorerController.Relationship>{
                    relates('ssot__EmailEngagement__dlm', 'ssot__IndividualId__c', 'ssot__Individual__dlm')
                }
            ),
            'ssot__AccountContact__dlm' => entity(
                'ssot__AccountContact__dlm',
                'Account Contact',
                new List<UnifiedDmoExplorerController.Field>{ field('ssot__Id__c', 'Account Contact Id', 'STRING') },
                new List<UnifiedDmoExplorerController.Relationship>{
                    relates('ssot__AccountContact__dlm', 'ssot__IndividualId__c', 'ssot__Individual__dlm')
                }
            ),
            'ssot__SalesOrder__dlm' => entity(
                'ssot__SalesOrder__dlm',
                'Sales Order',
                new List<UnifiedDmoExplorerController.Field>{
                    field('ssot__OrderNumber__c', 'Order Number', 'STRING'),
                    field('ssot__GrandTotalAmount__c', 'Grand Total', 'NUMBER')
                },
                new List<UnifiedDmoExplorerController.Relationship>{
                    relates('ssot__SalesOrder__dlm', 'ssot__BillToContactId__c', 'ssot__AccountContact__dlm')
                }
            ),
            'ssot__Product__dlm' => entity(
                'ssot__Product__dlm',
                'Product',
                new List<UnifiedDmoExplorerController.Field>{ field('ssot__Id__c', 'Product Id', 'STRING') },
                new List<UnifiedDmoExplorerController.Relationship>()
            )
        };
    }

    @IsTest
    static void thePickerSaysHowEachObjectReachesTheIndividual() {
        seedCatalogue();

        Map<String, UnifiedDmoExplorerController.ObjectOption> byName = new Map<String, UnifiedDmoExplorerController.ObjectOption>();
        for (UnifiedDmoExplorerController.ObjectOption o : UnifiedDmoExplorerController.getRelatedObjects(UNIFIED_DMO)) {
            byName.put(o.apiName, o);
        }

        Assert.areEqual(3, byName.size(), 'The individual itself and unrelated objects are left out');
        Assert.isTrue(byName.get('ssot__EmailEngagement__dlm').isDirect);
        Assert.areEqual('Points at Individual', byName.get('ssot__EmailEngagement__dlm').relationship);
        Assert.areEqual('ssot__IndividualId__c', byName.get('ssot__EmailEngagement__dlm').suggestedKey);

        Assert.isFalse(byName.get('ssot__SalesOrder__dlm').isDirect);
        Assert.areEqual(
            'Reaches the individual through Account Contact',
            byName.get('ssot__SalesOrder__dlm').relationship
        );
        Assert.areEqual('ssot__BillToContactId__c', byName.get('ssot__SalesOrder__dlm').suggestedKey);
        Assert.isNull(byName.get('ssot__Product__dlm'), 'Two hops away is too far to offer');
    }

    @IsTest
    static void anObjectOffersItsMappedFieldsAndAKeyToMatchOn() {
        seedCatalogue();

        UnifiedDmoExplorerController.ObjectDetail detail = UnifiedDmoExplorerController.describeObject(
            'ssot__EmailEngagement__dlm',
            UNIFIED_DMO
        );

        Assert.areEqual('Email Engagement', detail.label);
        Assert.areEqual(2, detail.fields.size(), 'The key qualifier column is not worth offering');
        Assert.areEqual('Engagement Date Time', detail.fields[0].label, 'Fields read in label order');
        Assert.areEqual('ssot__IndividualId__c', detail.suggestedKey);
    }

    @IsTest
    static void aSearchNeedsAFieldAndAKeyTheObjectActuallyHas() {
        seedCatalogue();

        for (List<String> fields : new List<List<String>>{
            new List<String>(),
            new List<String>{ 'not_a_column__c' },
            null
        }) {
            try {
                UnifiedDmoExplorerController.search(
                    UNIFIED_ID,
                    UNIFIED_DMO,
                    'ssot__EmailEngagement__dlm',
                    fields,
                    'ssot__IndividualId__c',
                    25
                );
                Assert.fail('A search with nothing to show should be refused');
            } catch (AuraHandledException e) {
                Assert.isNotNull(e.getMessage());
            }
        }
    }

    @IsTest
    static void aProfileWithNoContributingRecordsHasNothingToMatchOn() {
        seedCatalogue();

        UnifiedDmoExplorerController.SearchResult result = UnifiedDmoExplorerController.search(
            null,
            UNIFIED_DMO,
            'ssot__EmailEngagement__dlm',
            new List<String>{ 'ssot__EngagementDateTm__c', 'ssot__EngagementDateTm__c' },
            'ssot__IndividualId__c',
            25
        );

        Assert.areEqual(1, result.columns.size(), 'A field chosen twice is one column');
        Assert.areEqual('Engagement Date Time', result.columns[0].label);
        Assert.areEqual('This profile has no contributing records to match on.', result.notice);
    }

    @IsTest
    static void aQueryTheServiceCannotRunIsReportedRatherThanSwallowed() {
        // The query service is unreachable from a test, which stands in for Data Cloud refusing
        // the query. The user is told, instead of being shown an empty table.
        seedCatalogue();

        Test.startTest();
        try {
            UnifiedDmoExplorerController.search(
                UNIFIED_ID,
                UNIFIED_DMO,
                'ssot__EmailEngagement__dlm',
                new List<String>{ 'ssot__EngagementDateTm__c' },
                'ssot__IndividualId__c',
                null
            );
            Assert.fail('The failure should reach the page');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void everyRowFillsTheHeadingsItSitsUnder() {
        // The query service returns columns in its own order, and a row can be missing a value
        // altogether. Each cell still has to land under its own heading.
        UnifiedDmoExplorerController.SearchResult result = new UnifiedDmoExplorerController.SearchResult();
        Map<String, UnifiedDmoExplorerController.Field> byName = new Map<String, UnifiedDmoExplorerController.Field>{
            'ssot__EngagementDateTm__c' => field('ssot__EngagementDateTm__c', 'Engagement Date Time', 'DATE_TIME'),
            'ssot__OrderNumber__c' => field('ssot__OrderNumber__c', 'Order Number', 'STRING')
        };

        UnifiedDmoExplorerController.addRows(
            result,
            new List<List<Object>>{
                new List<Object>{ 'SO-1001', '2026-06-05 08:00:44.857 UTC' },
                new List<Object>{ 'SO-1002' }
            },
            new List<String>{ 'ssot__EngagementDateTm__c', 'ssot__OrderNumber__c' },
            new Map<String, Integer>{ 'ssot__OrderNumber__c' => 0, 'ssot__EngagementDateTm__c' => 1 },
            byName,
            'ssot__EmailEngagement__dlm'
        );

        Assert.areEqual(2, result.rows.size());
        Assert.areEqual('ssot__EmailEngagement__dlm-0', result.rows[0].key);
        Assert.areEqual('2026-06-05T08:00:44.857Z', result.rows[0].cells[0], 'Read from the place the service used');
        Assert.areEqual('SO-1001', result.rows[0].cells[1]);
        Assert.areEqual(2, result.rows[1].cells.size(), 'A short row still fills both headings');
        Assert.areEqual('', result.rows[1].cells[0], 'An empty cell is blank, never dropped');
    }

    @IsTest
    static void rowsAreOrderedByADateTheObjectHolds() {
        seedCatalogue();
        UnifiedDmoExplorerController.Entity engagement = UnifiedDmoExplorerController.cachedCatalogue.get(
            'ssot__EmailEngagement__dlm'
        );

        Assert.areEqual(
            'ssot__EngagementDateTm__c',
            UnifiedDmoExplorerController.newestFirstColumn(
                engagement,
                new List<String>{ 'ssot__IndividualId__c', 'ssot__EngagementDateTm__c' }
            ),
            'A date the user chose to show is the one to sort on'
        );
        Assert.areEqual(
            'ssot__EngagementDateTm__c',
            UnifiedDmoExplorerController.newestFirstColumn(engagement, new List<String>{ 'ssot__IndividualId__c' }),
            'Otherwise any date the object holds'
        );
        Assert.isNull(
            UnifiedDmoExplorerController.newestFirstColumn(
                UnifiedDmoExplorerController.cachedCatalogue.get('ssot__SalesOrder__dlm'),
                new List<String>{ 'ssot__OrderNumber__c' }
            ),
            'An object with no date is left in the order it comes back in'
        );
    }

    @IsTest
    static void theProfilesOwnRulesetCountsAsTheIndividual() {
        Assert.isTrue(
            UnifiedDmoExplorerController.individualRoots('UnifiedssotIndividualMc__dlm')
                .contains('unifiedssotindividualmc__dlm'),
            'Whichever ruleset the page is on is one of the roots'
        );
        Assert.isTrue(
            UnifiedDmoExplorerController.individualRoots(null).contains('ssot__individual__dlm'),
            'The source individual is always a root'
        );
    }
}
