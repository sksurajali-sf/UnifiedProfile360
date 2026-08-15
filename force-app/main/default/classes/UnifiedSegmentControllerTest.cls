/**
 * Membership lives in Data Cloud, which an Apex test cannot query, so these cover the parts
 * that decide what is asked for and how the answer is presented: the per-ruleset table prefix,
 * the timestamp format the query service returns, and the guard clauses. The query path itself
 * is verified against live org data by scripts/apex/probeSegments.apex.
 */
@IsTest
private class UnifiedSegmentControllerTest {
    @IsTest
    static void tablePrefixFollowsTheRuleset() {
        // The numeric suffix differs per org, so only the leading part is derived; the rest is
        // read from MarketSegment.SegmentMembershipTable at runtime.
        Assert.areEqual(
            'Individual_Unified_SM',
            UnifiedProfileRegistry.resolve('UnifiedIndividual__dlm').segmentTablePrefix
        );
        Assert.areEqual(
            'ssotIndividualMc_Unified_SM',
            UnifiedProfileRegistry.resolve('UnifiedssotIndividualMc__dlm').segmentTablePrefix
        );
        Assert.areEqual(
            'ssotIndividualPoc1_Unified_SM',
            UnifiedProfileRegistry.resolve('UnifiedssotIndividualPoc1__dlm').segmentTablePrefix
        );
    }

    @IsTest
    static void blankProfileNeverReachesTheQueryService() {
        UnifiedSegmentController.SegmentResult result = UnifiedSegmentController.getSegments(
            null,
            'UnifiedIndividual__dlm'
        );

        Assert.isNotNull(result);
        Assert.areEqual(0, result.segments.size());
        Assert.isFalse(result.truncated);
    }

    @IsTest
    static void queryServiceTimestampsAreParsed() {
        // Membership rows come back as "2026-07-28 08:49:19.151 UTC", which is not a format
        // Datetime.valueOf accepts.
        Datetime parsed = UnifiedSegmentController.parseTimestamp('2026-07-28 08:49:19.151 UTC');
        Assert.areEqual(Datetime.newInstanceGmt(2026, 7, 28, 8, 49, 19), parsed);

        Assert.areEqual(
            Datetime.newInstanceGmt(2026, 7, 28, 8, 49, 19),
            UnifiedSegmentController.parseTimestamp('2026-07-28T08:49:19Z')
        );
        Assert.isNull(UnifiedSegmentController.parseTimestamp('  '));
        Assert.isNull(UnifiedSegmentController.parseTimestamp('not a timestamp'));
    }

    @IsTest
    static void statusAndScheduleAreReadable() {
        Assert.areEqual('Active', UnifiedSegmentController.prettify('ACTIVE'));
        Assert.areEqual('No refresh', UnifiedSegmentController.prettify('NO_REFRESH'));
        Assert.areEqual('Twelve hours', UnifiedSegmentController.prettify('TWELVE_HOURS'));
        Assert.isNull(UnifiedSegmentController.prettify(null));
    }

    @IsTest
    static void weeklyScheduleReadsLikeTheSegmentsOwnProperties() {
        // Exactly what MarketSegment.PublishScheduleInfo holds for a segment set to run weekly
        // on Monday. PublishScheduleInterval alone would read as a bare "24".
        String info =
            '{"hourlyInterval":"24","frequency":1,"scheduleFrequency":"WEEKLY",' +
            '"runStartTimeForRapid":null,"runEndTimeForRapid":null,"scheduledDays":["MON"],' +
            '"runTimezone":"UTC","endTimeInfo":{"never":true,"expirationTime":null},' +
            '"monthlyInfo":{"isLastDay":null,"dayOfMonth":null}}';

        Assert.areEqual('Weekly on Mon', UnifiedSegmentController.scheduleLabel(info, '24'));
    }

    @IsTest
    static void everyCadenceGetsItsOwnWording() {
        Assert.areEqual(
            'Every 2 weeks on Mon, Thu',
            UnifiedSegmentController.scheduleLabel(
                '{"hourlyInterval":"24","frequency":2,"scheduleFrequency":"WEEKLY","scheduledDays":["MON","THU"]}',
                '24'
            )
        );
        Assert.areEqual(
            'Daily',
            UnifiedSegmentController.scheduleLabel(
                '{"hourlyInterval":"24","frequency":1,"scheduleFrequency":"DAILY"}',
                '24'
            )
        );
        Assert.areEqual(
            'Every 6 hours',
            UnifiedSegmentController.scheduleLabel(
                '{"hourlyInterval":"6","frequency":1,"scheduleFrequency":"DAILY"}',
                '6'
            )
        );
        Assert.areEqual(
            'Monthly on day 5',
            UnifiedSegmentController.scheduleLabel(
                '{"hourlyInterval":"24","frequency":1,"scheduleFrequency":"MONTHLY","monthlyInfo":{"dayOfMonth":5}}',
                '24'
            )
        );
        Assert.areEqual(
            'Every 3 months on the last day',
            UnifiedSegmentController.scheduleLabel(
                '{"hourlyInterval":"24","frequency":3,"scheduleFrequency":"MONTHLY","monthlyInfo":{"isLastDay":true}}',
                '24'
            )
        );
    }

    @IsTest
    static void unscheduledSegmentsSayNoRefresh() {
        Assert.areEqual('No refresh', UnifiedSegmentController.scheduleLabel(null, 'NO_REFRESH'));
        Assert.areEqual('No refresh', UnifiedSegmentController.scheduleLabel('not json', 'NO_REFRESH'));
        Assert.areEqual('No refresh', UnifiedSegmentController.scheduleLabel('{"scheduleFrequency":null}', null));
    }

    @IsTest
    static void segmentsSortByMostRecentPublish() {
        UnifiedSegmentController.SegmentRow older = new UnifiedSegmentController.SegmentRow();
        older.name = 'Older';
        older.lastPublished = Datetime.newInstanceGmt(2026, 6, 1, 0, 0, 0);

        UnifiedSegmentController.SegmentRow newer = new UnifiedSegmentController.SegmentRow();
        newer.name = 'Newer';
        newer.lastPublished = Datetime.newInstanceGmt(2026, 7, 28, 0, 0, 0);

        UnifiedSegmentController.SegmentRow neverPublished = new UnifiedSegmentController.SegmentRow();
        neverPublished.name = 'Draft';

        List<UnifiedSegmentController.SegmentRow> rows = new List<UnifiedSegmentController.SegmentRow>{
            older,
            neverPublished,
            newer
        };
        rows.sort();

        Assert.areEqual('Newer', rows[0].name);
        Assert.areEqual('Older', rows[1].name);
        Assert.areEqual('Draft', rows[2].name, 'Unpublished segments sort last');
    }

    @IsTest
    static void twoSegmentsPublishedTogetherSortByName() {
        Datetime published = Datetime.newInstanceGmt(2026, 7, 28, 0, 0, 0);
        UnifiedSegmentController.SegmentRow first = new UnifiedSegmentController.SegmentRow();
        first.name = 'Anniversary';
        first.lastPublished = published;
        UnifiedSegmentController.SegmentRow second = new UnifiedSegmentController.SegmentRow();
        second.name = 'Winback';
        second.lastPublished = published;
        UnifiedSegmentController.SegmentRow unnamed = new UnifiedSegmentController.SegmentRow();
        unnamed.lastPublished = published;

        List<UnifiedSegmentController.SegmentRow> rows = new List<UnifiedSegmentController.SegmentRow>{
            second,
            unnamed,
            first
        };
        rows.sort();

        Assert.areEqual('Anniversary', rows[0].name);
        Assert.areEqual('Winback', rows[1].name);
        Assert.isNull(rows[2].name);
        Assert.areEqual(0, first.compareTo(first));
    }

    @IsTest
    static void aProfileInNoSegmentsIsToldWhichRulesetWasLookedAt() {
        // No segment in the org is built on this ruleset, so there is no membership table to read.
        UnifiedSegmentController.SegmentResult result = UnifiedSegmentController.getSegments(
            '0f4a1c9e8b2d47f3a6c50e19b7d83af2',
            'UnifiedssotIndividualMc__dlm'
        );

        Assert.areEqual(0, result.segments.size());
        Assert.areEqual(
            'No published segments are built on UnifiedssotIndividualMc__dlm.',
            result.notice
        );
    }

    @IsTest
    static void membershipTablesAreFoundByTheirRulesetPrefix() {
        // A test sees no segments, so the list is empty; what matters is that a blank prefix
        // never reaches a query and an underscore in the prefix is not read as a wildcard.
        Assert.areEqual(0, UnifiedSegmentController.membershipTables('', '').size());
        Assert.areEqual(0, UnifiedSegmentController.membershipTables('Individual_Unified_SM', '').size());
        Assert.areEqual(
            0,
            UnifiedSegmentController.membershipTables('IndividualApx1_Unified_SM', 'apj_').size(),
            'A renamed space is looked up under both spellings'
        );
    }

    @IsTest
    static void anUnreadableTableLeavesThePanelEmptyRatherThanBroken() {
        // The query service cannot be reached from a test, which stands in for a membership
        // table this org cannot read.
        Test.startTest();
        Map<String, UnifiedSegmentController.Membership> memberships = UnifiedSegmentController.readMemberships(
            new List<String>{ 'Individual_Unified_SMH_178239085__dlm' },
            '0f4a1c9e8b2d47f3a6c50e19b7d83af2',
            'default'
        );
        Test.stopTest();

        Assert.areEqual(0, memberships.size());
    }

    @IsTest
    static void aProfileThatHasLeftASegmentIsNotShownInIt() {
        Map<String, UnifiedSegmentController.Membership> memberships = new Map<String, UnifiedSegmentController.Membership>();

        UnifiedSegmentController.collectMemberships(
            memberships,
            new List<List<Object>>{
                new List<Object>{ '0YtKh0000001aaa', 'new', '2026-07-28 08:49:19.151 UTC' },
                new List<Object>{ '0YtKh0000001bbb', 'update', '2026-07-20 06:00:00.000 UTC' },
                new List<Object>{ '0YtKh0000001ccc', 'removed', '2026-07-27 06:00:00.000 UTC' },
                new List<Object>{ '', 'new', '2026-07-27 06:00:00.000 UTC' }
            },
            0,
            1,
            2
        );

        Assert.areEqual(2, memberships.size(), 'The exited membership and the unkeyed row are left out');
        Assert.isTrue(memberships.get('0YtKh0000001aaa').isNew);
        Assert.areEqual(
            Datetime.newInstanceGmt(2026, 7, 28, 8, 49, 19),
            memberships.get('0YtKh0000001aaa').since
        );
        Assert.isFalse(memberships.get('0YtKh0000001bbb').isNew);
    }

    @IsTest
    static void aMembershipWithNoDeltaColumnIsStillAMembership() {
        Map<String, UnifiedSegmentController.Membership> memberships = new Map<String, UnifiedSegmentController.Membership>();

        UnifiedSegmentController.collectMemberships(
            memberships,
            new List<List<Object>>{ new List<Object>{ '0YtKh0000001aaa' } },
            0,
            -1,
            -1
        );

        Assert.areEqual(1, memberships.size());
        Assert.isNull(memberships.get('0YtKh0000001aaa').since);
        Assert.isNull(UnifiedSegmentController.valueAt(new List<Object>{ 'a' }, 5), 'Past the end of the row');
        Assert.isNull(UnifiedSegmentController.valueAt(new List<Object>{ null }, 0));
    }

    /** MarketSegment fields are read only, so a record is built the way the platform returns one. */
    private static MarketSegment segment(Map<String, Object> fields) {
        Map<String, Object> raw = new Map<String, Object>{
            'attributes' => new Map<String, String>{ 'type' => 'MarketSegment' },
            'Id' => Id.valueOf(MarketSegment.SObjectType.getDescribe().getKeyPrefix() + '000000000001')
        };
        raw.putAll(fields);
        return (MarketSegment) JSON.deserialize(JSON.serialize(raw), MarketSegment.class);
    }

    @IsTest
    static void aSegmentIsDescribedAsItsOwnPropertiesDialogWould() {
        Datetime published = Datetime.newInstanceGmt(2026, 7, 28, 6, 0, 0);
        MarketSegment s = segment(
            new Map<String, Object>{
                'Name' => 'High Value Shoppers',
                'SegmentStatus' => 'ACTIVE',
                'PublishStatus' => 'SUCCESS',
                'MarketSegmentType' => 'STANDARD',
                'PublishType' => 'FULL',
                'PublishScheduleInterval' => '24',
                'LastSegmentMemberCount' => 128394,
                'PublishScheduleInfo' => '{"hourlyInterval":"24","frequency":1,"scheduleFrequency":"WEEKLY","scheduledDays":["MON"]}',
                'LastPublishedEndDateTime' => published
            }
        );

        UnifiedSegmentController.Membership membership = new UnifiedSegmentController.Membership();
        membership.since = published;
        membership.isNew = true;

        List<UnifiedSegmentController.SegmentRow> rows = UnifiedSegmentController.describeSegments(
            new List<MarketSegment>{ s },
            // Membership rows carry the 15 character form of the id.
            new Map<String, UnifiedSegmentController.Membership>{ String.valueOf(s.Id).substring(0, 15) => membership }
        );

        Assert.areEqual(1, rows.size());
        Assert.areEqual('High Value Shoppers', rows[0].name);
        Assert.areEqual('Active', rows[0].status);
        Assert.areEqual('Success', rows[0].publishStatus);
        Assert.areEqual('Weekly on Mon', rows[0].schedule, 'Not the bare hour count the interval holds');
        Assert.areEqual('Full', rows[0].publishType);
        Assert.areEqual(128394, rows[0].memberCount);
        Assert.areEqual(published, rows[0].memberSince);
        Assert.isTrue(rows[0].isNewMember);
    }

    @IsTest
    static void aSegmentThisProfileIsNotInCarriesNoMembershipDates() {
        List<UnifiedSegmentController.SegmentRow> rows = UnifiedSegmentController.describeSegments(
            new List<MarketSegment>{ segment(new Map<String, Object>{ 'Name' => 'Anniversary' }) },
            new Map<String, UnifiedSegmentController.Membership>()
        );

        Assert.isNull(rows[0].memberSince);
        Assert.isFalse(rows[0].isNewMember);
        Assert.isNull(rows[0].status, 'Nothing to prettify means nothing to show');
    }

    @IsTest
    static void aScheduleSetOnAnOddDayStillReads() {
        Assert.areEqual(
            'Hourly',
            UnifiedSegmentController.scheduleLabel('{"hourlyInterval":"1","scheduleFrequency":"HOURLY"}', '1')
        );
        Assert.areEqual(
            'Weekly',
            UnifiedSegmentController.scheduleLabel('{"hourlyInterval":"24","frequency":1,"scheduleFrequency":"WEEKLY"}', '24'),
            'A weekly schedule with no days named still says weekly'
        );
        Assert.areEqual(
            'Weekly on Mon, Xyz',
            UnifiedSegmentController.scheduleLabel(
                '{"hourlyInterval":"24","frequency":1,"scheduleFrequency":"WEEKLY","scheduledDays":["MON","XYZ"]}',
                '24'
            ),
            'A day code nobody recognises is shown rather than dropped'
        );
        Assert.areEqual(
            'Monthly',
            UnifiedSegmentController.scheduleLabel(
                '{"hourlyInterval":"24","frequency":1,"scheduleFrequency":"MONTHLY","monthlyInfo":{}}',
                '24'
            )
        );
        Assert.areEqual(
            'Rapid',
            UnifiedSegmentController.scheduleLabel(
                '{"hourlyInterval":"24","frequency":1,"scheduleFrequency":"RAPID"}',
                '24'
            ),
            'A cadence this page has never seen is shown as the platform names it'
        );
        Assert.areEqual(
            'No refresh',
            UnifiedSegmentController.scheduleLabel('{"hourlyInterval":"nonsense","scheduleFrequency":null}', '24'),
            'A segment with no cadence named is not on a schedule'
        );
    }
}
