/**
 * The Data Cloud query service is a callout and is not invokable from a test context, so
 * these tests drive the parsing, validation and failure handling around it.
 */
@IsTest
private class UnifiedInsightControllerTest {
    private static final String UNIFIED_DMO = 'UnifiedIndividual__dlm';
    private static final String SAMPLE_ID = '63140befab102a389764c0b204cb81e0';

    @IsTest
    static void fallbackNamesParseFromCsv() {
        List<String> names = UnifiedInsightController.splitNames('Lifetime_Purchase_Count__cio, Total_Visits__cio');

        Assert.areEqual(2, names.size());
        Assert.areEqual('Lifetime_Purchase_Count__cio', names[0]);
        Assert.areEqual('Total_Visits__cio', names[1]);
    }

    @IsTest
    static void fallbackNamesRejectUnsafeInput() {
        List<String> names = UnifiedInsightController.splitNames('Good_Name__cio, bad name; DROP, , Another__cio');

        Assert.areEqual(2, names.size(), 'Only well-formed API names should survive');
        Assert.areEqual('Good_Name__cio', names[0]);
        Assert.areEqual('Another__cio', names[1]);
    }

    @IsTest
    static void fallbackNamesHandleBlankInput() {
        Assert.areEqual(0, UnifiedInsightController.splitNames(null).size());
        Assert.areEqual(0, UnifiedInsightController.splitNames('').size());
        Assert.areEqual(0, UnifiedInsightController.splitNames('   ').size());
    }

    @IsTest
    static void labelsAreHumanised() {
        Assert.areEqual('Lifetime Purchase Count', UnifiedInsightController.prettify('Lifetime_Purchase_Count__cio'));
        Assert.areEqual('Profile Count', UnifiedInsightController.prettify('profile_count__c'));
        Assert.areEqual('', UnifiedInsightController.prettify(null));
    }

    @IsTest
    static void optionsSurviveWithoutAQueryService() {
        // The catalogue and the per-insight probe both need services a test context cannot
        // reach. The picker must still come back as a list rather than an exception.
        Test.startTest();
        List<UnifiedInsightController.InsightOption> options = UnifiedInsightController.getInsightOptions(
            'Lifetime_Purchase_Count__cio'
        );
        Test.stopTest();

        Assert.isNotNull(options);
    }

    @IsTest
    static void insightDataRejectsBlankName() {
        UnifiedInsightController.InsightResult result = UnifiedInsightController.getInsightData(
            '',
            SAMPLE_ID,
            UNIFIED_DMO
        );

        Assert.isFalse(result.found);
        Assert.areEqual('Select a calculated insight.', result.message);
    }

    @IsTest
    static void insightDataRejectsUnsafeName() {
        UnifiedInsightController.InsightResult result = UnifiedInsightController.getInsightData(
            'bad name; DROP TABLE',
            SAMPLE_ID,
            UNIFIED_DMO
        );

        Assert.isFalse(result.found);
        Assert.areEqual('Select a calculated insight.', result.message);
    }

    @IsTest
    static void insightDataRequiresUnifiedId() {
        UnifiedInsightController.InsightResult result = UnifiedInsightController.getInsightData(
            'Lifetime_Purchase_Count__cio',
            null,
            UNIFIED_DMO
        );

        Assert.isFalse(result.found);
        Assert.areEqual('This profile has no unified id.', result.message);
    }

    @IsTest
    static void insightDataDegradesWhenQueryServiceUnavailable() {
        // The query service cannot be reached from a test context; the component must still
        // receive a populated result rather than an exception.
        Test.startTest();
        UnifiedInsightController.InsightResult result = UnifiedInsightController.getInsightData(
            'Lifetime_Purchase_Count__cio',
            SAMPLE_ID,
            UNIFIED_DMO
        );
        Test.stopTest();

        Assert.isNotNull(result);
        Assert.areEqual('Lifetime_Purchase_Count__cio', result.apiName);
        Assert.areEqual('Lifetime Purchase Count', result.label);
        Assert.isFalse(result.found);
        Assert.isNotNull(result.message, 'A reason must be surfaced to the user');
    }

    @IsTest
    static void anInsightNotKeyedByAProfileSaysSo() {
        // Inspected and found to hold no unified individual column: it cannot be shown against
        // this profile, and the user is told why rather than left with an empty panel.
        UnifiedInsightController.keyFieldCache.put('Store_Footfall__cio', '');

        UnifiedInsightController.InsightResult result = UnifiedInsightController.getInsightData(
            'Store_Footfall__cio',
            SAMPLE_ID,
            UNIFIED_DMO
        );

        Assert.isFalse(result.found);
        Assert.areEqual('Store Footfall is not keyed by a unified individual id.', result.message);
    }

    @IsTest
    static void anInspectedInsightIsOfferedWithItsKeyColumn() {
        UnifiedInsightController.keyFieldCache.put('Lifetime_Purchase_Count__cio', 'unified_individual_id__c');
        UnifiedInsightController.keyFieldCache.put('Store_Footfall__cio', '');

        List<UnifiedInsightController.InsightOption> options = UnifiedInsightController.getInsightOptions(
            'Lifetime_Purchase_Count__cio, Store_Footfall__cio'
        );

        Assert.areEqual(1, options.size(), 'The unkeyed insight is left out of the picker');
        Assert.areEqual('Lifetime_Purchase_Count__cio', options[0].apiName);
        Assert.areEqual('Lifetime Purchase Count', options[0].label);
        Assert.areEqual('unified_individual_id__c', options[0].keyField);
    }

    @IsTest
    static void theProfileKeyIsFoundWhateverTheInsightCallsIt() {
        Assert.areEqual(
            'ssot__unified_individual_id__c',
            UnifiedInsightController.findKeyField(
                new List<String>{ 'count__c', 'ssot__unified_individual_id__c', 'profile_id__c' }
            )
        );
        Assert.areEqual(
            'UnifiedIndividualId__c',
            UnifiedInsightController.findKeyField(new List<String>{ 'UnifiedIndividualId__c' })
        );
        Assert.areEqual(
            'profile_id__c',
            UnifiedInsightController.findKeyField(new List<String>{ 'KQ_profile_id__c', 'profile_id__c' }),
            'A key qualifier column is not the key'
        );
        Assert.isNull(UnifiedInsightController.findKeyField(new List<String>{ 'store_id__c', 'visits__c' }));
    }

    @IsTest
    static void measuresAndDimensionsAreSplitApart() {
        UnifiedInsightController.InsightRow row = UnifiedInsightController.buildRow(
            new List<Object>{ 'uid-1', 'Bengaluru', 4823.5, 'kq-noise', null },
            new Map<Integer, String>{
                0 => 'unified_individual_id__c',
                1 => 'store_city__c',
                2 => 'net_purchase_amount__c',
                3 => 'KQ_source__c',
                4 => 'last_channel__c'
            },
            new Map<String, String>{
                'unified_individual_id__c' => 'VARCHAR',
                'store_city__c' => 'VARCHAR',
                'net_purchase_amount__c' => 'DECIMAL',
                'KQ_source__c' => 'VARCHAR',
                'last_channel__c' => 'VARCHAR'
            },
            'unified_individual_id__c'
        );

        Assert.areEqual(1, row.measures.size(), 'Only the numeric column is a measure');
        Assert.areEqual('Net Purchase Amount', row.measures[0].label);
        Assert.areEqual(4823.5, row.measures[0].value);
        Assert.isTrue(row.measures[0].isNumber);

        Assert.areEqual(1, row.dimensions.size(), 'The key, the qualifier and the empty column are all left out');
        Assert.areEqual('Store City', row.dimensions[0].label);
        Assert.areEqual('Bengaluru', row.dimensions[0].textValue);
    }

    @IsTest
    static void aMeasureThatIsNotANumberIsShownAsEmptyRatherThanWrong() {
        UnifiedInsightController.InsightRow row = UnifiedInsightController.buildRow(
            new List<Object>{ 'not a number' },
            new Map<Integer, String>{ 0 => 'net_purchase_amount__c', 1 => 'missing_from_the_row__c' },
            new Map<String, String>{
                'net_purchase_amount__c' => 'DECIMAL',
                'missing_from_the_row__c' => 'VARCHAR'
            },
            'unified_individual_id__c'
        );

        Assert.areEqual(1, row.measures.size());
        Assert.isNull(row.measures[0].value);
        Assert.areEqual(0, row.dimensions.size(), 'A column the row has no value for shows nothing');
        Assert.isNull(UnifiedInsightController.toDecimal(null));
    }

    @IsTest
    static void plumbingColumnsAreNeverShown() {
        Assert.isTrue(UnifiedInsightController.isNoise('KQ_individual_id__c'));
        Assert.isTrue(UnifiedInsightController.isNoise('individual_id_kq__c'));
        Assert.isTrue(UnifiedInsightController.isNoise('cdp_sys_partition__c'));
        Assert.isFalse(UnifiedInsightController.isNoise('net_purchase_amount__c'));
    }

    @IsTest
    static void aProfileKeyWithAQuoteInItCannotBreakOutOfTheSql() {
        Assert.areEqual('O\'\'Brien', UnifiedInsightController.escapeLiteral('O\'Brien'));
    }

    @IsTest
    static void theCatalogueIsReadFromThePlatformWhenItCanBe() {
        // In a test the insight objects hold no rows, which is the same as an org with none:
        // the picker falls back to whatever the page was configured with.
        Assert.isNotNull(UnifiedInsightController.catalogueApiNames());
    }

    /** What the query service hands back, in the shape it hands it back in. */
    private static ConnectApi.CdpQueryOutputV2 serviceOutput(
        List<String> columns,
        List<String> types,
        List<List<Object>> rows
    ) {
        ConnectApi.CdpQueryOutputV2 output = new ConnectApi.CdpQueryOutputV2();
        output.metadata = new Map<String, ConnectApi.CdpQueryMetadataItem>();
        for (Integer i = 0; i < columns.size(); i++) {
            ConnectApi.CdpQueryMetadataItem item = new ConnectApi.CdpQueryMetadataItem();
            item.placeInOrder = i;
            item.type = types[i];
            output.metadata.put(columns[i], item);
        }
        output.data = new List<ConnectApi.CdpQueryV2Row>();
        for (List<Object> row : rows) {
            ConnectApi.CdpQueryV2Row r = new ConnectApi.CdpQueryV2Row();
            r.rowData = row;
            output.data.add(r);
        }
        return output;
    }

    private static UnifiedInsightController.InsightResult resultFor(String apiName, String keyField) {
        UnifiedInsightController.InsightResult result = new UnifiedInsightController.InsightResult();
        result.apiName = apiName;
        result.label = UnifiedInsightController.prettify(apiName);
        result.keyField = keyField;
        return result;
    }

    @IsTest
    static void anInsightKeyedByDimensionsShowsOneRowPerCombination() {
        UnifiedInsightController.InsightResult result = resultFor('Purchases_By_Channel__cio', 'unified_individual_id__c');

        UnifiedInsightController.applyRows(
            result,
            serviceOutput(
                new List<String>{ 'unified_individual_id__c', 'channel__c', 'net_purchase_amount__c' },
                new List<String>{ 'VARCHAR', 'VARCHAR', 'DECIMAL' },
                new List<List<Object>>{
                    new List<Object>{ SAMPLE_ID, 'Web', 4823.5 },
                    new List<Object>{ SAMPLE_ID, 'Store', 1190 }
                }
            ),
            'Purchases_By_Channel__cio'
        );

        Assert.isTrue(result.found);
        Assert.areEqual(2, result.rows.size());
        Assert.areEqual('Purchases_By_Channel__cio-0', result.rows[0].key);
        Assert.areEqual('Web', result.rows[0].dimensions[0].textValue);
        Assert.areEqual(4823.5, result.rows[0].measures[0].value);
        Assert.areEqual('Store', result.rows[1].dimensions[0].textValue);
        Assert.isNull(result.message);
    }

    @IsTest
    static void anInsightWithNoRowForThisProfileSaysSoRatherThanShowingZero() {
        UnifiedInsightController.InsightResult result = resultFor('Lifetime_Purchase_Count__cio', 'unified_individual_id__c');

        UnifiedInsightController.applyRows(
            result,
            serviceOutput(
                new List<String>{ 'unified_individual_id__c' },
                new List<String>{ 'VARCHAR' },
                new List<List<Object>>()
            ),
            'Lifetime_Purchase_Count__cio'
        );

        Assert.isFalse(result.found);
        Assert.areEqual('No Lifetime Purchase Count value for this profile.', result.message);
        Assert.areEqual(0, result.rows.size());
    }

    @IsTest
    static void anInsightOfNothingButPlumbingHasNothingToShow() {
        UnifiedInsightController.InsightResult result = resultFor('Lifetime_Purchase_Count__cio', 'unified_individual_id__c');

        UnifiedInsightController.applyRows(
            result,
            serviceOutput(
                new List<String>{ 'unified_individual_id__c', 'KQ_source__c' },
                new List<String>{ 'VARCHAR', 'VARCHAR' },
                new List<List<Object>>{ new List<Object>{ SAMPLE_ID, 'crm' } }
            ),
            'Lifetime_Purchase_Count__cio'
        );

        Assert.isFalse(result.found);
        Assert.areEqual('Lifetime Purchase Count has no measures to show.', result.message);
    }

    @IsTest
    static void thePickerStopsInspectingOnceItHasEnoughToOffer() {
        // Every candidate costs a callout to inspect, so an org with dozens of insights is
        // capped rather than left waiting.
        List<String> names = new List<String>();
        for (Integer i = 0; i < 20; i++) {
            String apiName = 'Insight_' + i + '__cio';
            names.add(apiName);
            UnifiedInsightController.keyFieldCache.put(apiName, 'unified_individual_id__c');
        }

        Assert.areEqual(15, UnifiedInsightController.getInsightOptions(String.join(names, ', ')).size());
    }

    @IsTest
    static void anInsightThatCannotBeInspectedIsKept() {
        // The probe needs the query service, which a test cannot reach. An insight that could
        // not be inspected stays in the picker so a transient failure empties nothing.
        Test.startTest();
        Assert.isNull(UnifiedInsightController.keyFieldFor('Never_Inspected__cio'));
        Assert.isNull(UnifiedInsightController.keyFieldFor('Never_Inspected__cio'), 'The failure is remembered');
        Test.stopTest();

        Assert.areEqual(
            1,
            UnifiedInsightController.getInsightOptions('Never_Inspected__cio').size(),
            'It is offered rather than dropped'
        );
    }
}
