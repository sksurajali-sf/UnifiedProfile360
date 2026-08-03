/**
 * A test sees no Data Cloud rows: DMO queries return nothing and the query service refuses to
 * run at all, so what these cover is everything either side of the data. Each endpoint is called
 * end to end against an empty org, which is also how the panels behave in an org where a DMO is
 * absent, and the logic that turns rows into what the page shows is exercised directly with rows
 * shaped like the ones Data Cloud returns. The live query paths are checked against real org data
 * by scripts/apex/validate.apex.
 */
@IsTest
private class UnifiedProfileControllerTest {
    private static final String UNIFIED_DMO = 'UnifiedIndividual__dlm';
    /** Profile Explorer hands the page a 32 character unified key, not a Salesforce id. */
    private static final String UNIFIED_ID = '0f4a1c9e8b2d47f3a6c50e19b7d83af2';

    @IsTest
    static void registryResolvesDefaultRuleset() {
        UnifiedProfileRegistry.DmoSet dmo = UnifiedProfileRegistry.resolve('UnifiedIndividual__dlm');
        Assert.areEqual('IndividualIdentityLink__dlm', dmo.individualLink);
        Assert.areEqual('UnifiedContactPointEmail__dlm', dmo.unifiedEmail);
        Assert.areEqual('ContactPointEmailIdentityLink__dlm', dmo.emailLink);
        Assert.areEqual('UnifiedContactPointPhone__dlm', dmo.unifiedPhone);
        Assert.areEqual('UnifiedContactPointAddress__dlm', dmo.unifiedAddress);
    }

    @IsTest
    static void registryDerivesRulesetSuffixes() {
        UnifiedProfileRegistry.DmoSet mc = UnifiedProfileRegistry.resolve('UnifiedssotIndividualMc__dlm');
        Assert.areEqual('UnifiedLinkssotIndividualMc__dlm', mc.individualLink);
        Assert.areEqual('UnifiedssotContactPointEmailMc__dlm', mc.unifiedEmail);
        Assert.areEqual('UnifiedLinkssotContactPointEmailMc__dlm', mc.emailLink);

        UnifiedProfileRegistry.DmoSet poc = UnifiedProfileRegistry.resolve('UnifiedssotIndividualPoc1__dlm');
        Assert.areEqual('UnifiedLinkssotIndividualPoc1__dlm', poc.individualLink);
        Assert.areEqual('UnifiedssotContactPointAddressPoc1__dlm', poc.unifiedAddress);
        Assert.areEqual('UnifiedLinkssotContactPointPhonePoc1__dlm', poc.phoneLink);
    }

    @IsTest
    static void theSuffixIsWhatTiesAProfileToItsRuleset() {
        // IdentityResolution.Suffix carries the same token as the DMO names, which is how the
        // header finds the run that built this profile.
        Assert.areEqual('Mc', UnifiedProfileRegistry.resolve('UnifiedssotIndividualMc__dlm').rulesetSuffix);
        Assert.areEqual('Poc1', UnifiedProfileRegistry.resolve('UnifiedssotIndividualPoc1__dlm').rulesetSuffix);
        // The default ruleset names its DMOs without a suffix, and holds none on the object either.
        Assert.areEqual('', UnifiedProfileRegistry.resolve('UnifiedIndividual__dlm').rulesetSuffix);
    }

    @IsTest
    static void aProfileWithNoRulesetRunStillReturnsAHeader() {
        // Test context sees no IdentityResolution rows, which stands in for an org that does not
        // expose the object. The header has to survive that and let the UI fall back.
        UnifiedProfileController.ProfileHeader header = UnifiedProfileController.getProfileHeader(
            '',
            'UnifiedssotIndividualMc__dlm'
        );
        Assert.isNotNull(header);
        Assert.isNull(header.resolutionLastRun);
    }

    @IsTest
    static void registryFallsBackWhenBlank() {
        UnifiedProfileRegistry.DmoSet dmo = UnifiedProfileRegistry.resolve(null);
        Assert.areEqual('UnifiedIndividual__dlm', dmo.unifiedIndividual);
        // Second call exercises the cache branch.
        Assert.areEqual('UnifiedIndividual__dlm', UnifiedProfileRegistry.resolve(null).unifiedIndividual);
    }

    @IsTest
    static void headerHandlesBlankRecordId() {
        UnifiedProfileController.ProfileHeader header = UnifiedProfileController.getProfileHeader('', UNIFIED_DMO);
        Assert.isNotNull(header);
        Assert.isNull(header.unifiedId);
        Assert.areEqual(UNIFIED_DMO, header.rulesetDmo);
    }

    @IsTest
    static void malformedRecordIdNeverReachesTheQueryLayer() {
        // Filtering a DMO by a bad row id fails with an uncatchable exception, so the guard has to
        // reject it first. Returning before any query is also what keeps this test runnable.
        UnifiedProfileController.ProfileHeader header = UnifiedProfileController.getProfileHeader(
            'qGu000FXu5D9C5hCCF',
            UNIFIED_DMO
        );

        Assert.isNotNull(header);
        Assert.isNull(header.unifiedId, 'A malformed row id resolves to no profile');
    }

    @IsTest
    static void contactPointBreakdownHandlesMissingProfile() {
        UnifiedProfileController.BreakdownSection section = UnifiedProfileController.getContactPointBreakdown(
            null,
            UNIFIED_DMO,
            'Email'
        );
        Assert.isNotNull(section);
        Assert.areEqual(0, section.rows.size());
    }

    @IsTest
    static void individualBreakdownHandlesMissingProfile() {
        UnifiedProfileController.BreakdownSection section = UnifiedProfileController.getIndividualBreakdown(
            null,
            UNIFIED_DMO
        );
        Assert.isNotNull(section);
        Assert.areEqual('Individuals', section.label);
        Assert.areEqual(0, section.rows.size());
    }

    @IsTest
    static void engagementTimelineHandlesMissingProfile() {
        Assert.areEqual(0, UnifiedProfileController.getEngagementTimeline(null, UNIFIED_DMO, 10).size());
    }

    @IsTest
    static void orderTimelineHandlesMissingProfile() {
        List<UnifiedProfileController.OrderRow> orders = UnifiedProfileController.getOrderTimeline(
            null,
            UNIFIED_DMO,
            5
        );
        Assert.areEqual(0, orders.size());
    }

    @IsTest
    static void sourceIdsAreQuotedAndEscapedForTheQueryService() {
        // Source record ids are interpolated into Data Cloud SQL, which takes no bind
        // variables, so the escaping is what keeps a quote in an id from breaking out.
        Assert.areEqual(
            '\'CUST1001\', \'O\'\'Brien\'',
            UnifiedProfileController.quotedList(new List<String>{ 'CUST1001', 'O\'Brien', '  ' })
        );
        Assert.areEqual('\'\'', UnifiedProfileController.quotedList(new List<String>()));
    }

    private static UnifiedProfileController.SourceRow row(String id, String value, Datetime created) {
        UnifiedProfileController.SourceRow r = new UnifiedProfileController.SourceRow();
        r.sourceRecordId = id;
        r.value = value;
        r.createdDate = created;
        r.dataSource = 'Src_' + id;
        return r;
    }

    private static UnifiedProfileController.BreakdownSection sectionOf(
        List<UnifiedProfileController.SourceRow> rows
    ) {
        UnifiedProfileController.BreakdownSection s = new UnifiedProfileController.BreakdownSection();
        s.rows = rows;
        s.totalCount = rows.size();
        return s;
    }

    @IsTest
    static void exactlyOneRowWinsWhenSeveralCarryTheSameValue() {
        // Three source individuals with the same reconciled name: the id the unified record is
        // attributed to decides, and the other two are agreement rather than winners.
        Datetime base = Datetime.newInstanceGmt(2026, 6, 25, 12, 0, 0);
        UnifiedProfileController.BreakdownSection section = sectionOf(
            new List<UnifiedProfileController.SourceRow>{
                row('REC-0001', 'Arjun Mehta', base),
                row('003Kh00001vPDYuIAO', 'Arjun Mehta', base.addDays(-1)),
                row('SFMC-X01', 'Arjun Mehta', base.addDays(4))
            }
        );

        UnifiedProfileController.applyWinnerEvidence(section, 'Arjun Mehta', '003Kh00001vPDYuIAO');

        Integer winners = 0;
        for (UnifiedProfileController.SourceRow r : section.rows) {
            if (r.isWinner) {
                winners++;
                Assert.areEqual('003Kh00001vPDYuIAO', r.sourceRecordId, 'The attributed row wins');
                Assert.isFalse(r.matchesWinner, 'The winner is not also flagged as merely matching');
            } else {
                Assert.isTrue(r.matchesWinner, 'Rows repeating the winning value are marked as agreeing');
            }
        }

        Assert.areEqual(1, winners, 'Only one row is highlighted');
        Assert.areEqual(3, section.winnerMatchCount, 'All three still count towards the agreement');
        Assert.areEqual(3, section.winnerSources.size());
        Assert.areEqual(base.addDays(4), section.winnerLatestDate);
    }

    @IsTest
    static void mostRecentCarrierWinsWithoutAnAttributedId() {
        // Contact point DMOs publish no attribution column, so recency stands in for the default
        // Most Recent reconciliation rule.
        Datetime base = Datetime.newInstanceGmt(2026, 6, 25, 12, 0, 0);
        UnifiedProfileController.BreakdownSection section = sectionOf(
            new List<UnifiedProfileController.SourceRow>{
                row('CP-1', 'a@example.com', base),
                row('CP-2', 'a@example.com', base.addDays(2)),
                row('CP-3', 'b@example.com', base.addDays(9))
            }
        );

        UnifiedProfileController.applyWinnerEvidence(section, 'a@example.com', null);

        Assert.isTrue(section.rows[1].isWinner, 'The newer of the two carriers wins');
        Assert.isTrue(section.rows[0].matchesWinner);
        Assert.isFalse(section.rows[2].isWinner, 'A different value never wins');
        Assert.isFalse(section.rows[2].matchesWinner);
        Assert.areEqual(2, section.winnerMatchCount);
        Assert.areEqual(
            'Most recently created of the records carrying the winning value.',
            section.winnerBasis
        );
    }

    @IsTest
    static void asecondUnifiedValueCannotClaimThePrimaryRow() {
        // A profile holding two emails lists the contributors of both. Only the ones behind the
        // primary value are in the running, whatever the other value's records look like.
        Datetime base = Datetime.newInstanceGmt(2026, 6, 25, 12, 0, 0);
        UnifiedProfileController.SourceRow gmailA = row('SRC-1', 'a@example.com', base);
        UnifiedProfileController.SourceRow gmailB = row('SRC-2', 'a@example.com', base.addDays(1));
        UnifiedProfileController.SourceRow hotmail = row('SRC-2', 'b@example.com', base.addDays(8));
        gmailA.unifiedRecordId = 'primary';
        gmailB.unifiedRecordId = 'primary';
        hotmail.unifiedRecordId = 'secondary';

        UnifiedProfileController.BreakdownSection section = sectionOf(
            new List<UnifiedProfileController.SourceRow>{ gmailA, gmailB, hotmail }
        );

        UnifiedProfileController.applyWinnerEvidence(section, 'a@example.com', 'SRC-1', 'primary');

        Assert.isTrue(gmailA.isWinner, 'The attributed record wins inside the primary value');
        Assert.isTrue(gmailB.matchesWinner);
        Assert.isFalse(hotmail.isWinner, 'The second unified value has no winner of its own');
        Assert.isFalse(hotmail.matchesWinner);
        Assert.areEqual(2, section.winnerMatchCount, 'Only the primary value is counted');
        Assert.areEqual(3, section.totalCount, 'Every contributing record is still listed');
    }

    @IsTest
    static void arerunOfTheRulesetDoesNotRedateAContribution() {
        // Divya's REC-0006 email is linked twice, on 25 and 29 June, because the ruleset ran
        // again. It is one contribution, dated from when it first joined the profile.
        Datetime joined = Datetime.newInstanceGmt(2026, 6, 25, 12, 15, 57);
        Datetime rerun = Datetime.newInstanceGmt(2026, 6, 29, 8, 12, 21);

        Map<String, UnifiedProfileController.SourceRow> byKey = new Map<String, UnifiedProfileController.SourceRow>();
        Assert.isTrue(
            UnifiedProfileController.mergeLink(byKey, 'REC-0006', row('REC-0006', 'a@example.com', rerun)),
            'The first link row is a new contribution'
        );
        Assert.isFalse(
            UnifiedProfileController.mergeLink(byKey, 'REC-0006', row('REC-0006', 'a@example.com', joined)),
            'The rerun is the same contribution, not a second row'
        );

        Assert.areEqual(1, byKey.size());
        Assert.areEqual(joined, byKey.get('REC-0006').createdDate);
    }

    @IsTest
    static void anUndatedLinkTakesADateWhenOneTurnsUp() {
        Datetime known = Datetime.newInstanceGmt(2026, 6, 25, 12, 15, 57);
        Map<String, UnifiedProfileController.SourceRow> byKey = new Map<String, UnifiedProfileController.SourceRow>();

        UnifiedProfileController.mergeLink(byKey, 'REC-0006', row('REC-0006', 'a@example.com', null));
        UnifiedProfileController.mergeLink(byKey, 'REC-0006', row('REC-0006', 'a@example.com', known));

        Assert.areEqual(known, byKey.get('REC-0006').createdDate);
    }

    @IsTest
    static void anEmptyUnifiedValueIsPassedOverAsThePrimary() {
        // Reconciliation can leave the contact point keyed to the profile with nothing mapped,
        // which is what left the header's address tile blank while populated values existed.
        Map<String, String> values = new Map<String, String>{
            'unified-key' => '',
            'other-1' => '146 Market St, California',
            'other-2' => '4209 Park Lane, Karnataka'
        };
        Map<String, Integer> links = new Map<String, Integer>{ 'other-1' => 2, 'other-2' => 1 };

        Assert.areEqual(
            'other-1',
            UnifiedProfileController.primaryUnifiedId(values, links, 'unified-key'),
            'The populated value the most records agreed on leads'
        );

        values.put('unified-key', '12 Attributed Way');
        Assert.areEqual(
            'unified-key',
            UnifiedProfileController.primaryUnifiedId(values, links, 'unified-key'),
            'A populated primary still wins'
        );
    }

    @IsTest
    static void anAllEmptySectionFallsBackToThePrimary() {
        Assert.areEqual(
            'unified-key',
            UnifiedProfileController.primaryUnifiedId(
                new Map<String, String>{ 'unified-key' => null, 'other' => '  ' },
                new Map<String, Integer>(),
                'unified-key'
            )
        );
    }

    @IsTest
    static void noRowIsHighlightedWithoutAWinningValue() {
        UnifiedProfileController.BreakdownSection section = sectionOf(
            new List<UnifiedProfileController.SourceRow>{ row('CP-1', 'a@example.com', null) }
        );

        UnifiedProfileController.applyWinnerEvidence(section, null, null);

        Assert.isFalse(section.rows[0].isWinner);
        Assert.areEqual(0, section.winnerMatchCount);
        Assert.isNull(section.winnerBasis);
    }

    @IsTest
    static void timelineEventSortsNullDatesLast() {
        UnifiedProfileController.TimelineEvent withDate = new UnifiedProfileController.TimelineEvent();
        withDate.eventDateTime = Datetime.now();
        UnifiedProfileController.TimelineEvent withoutDate = new UnifiedProfileController.TimelineEvent();
        UnifiedProfileController.TimelineEvent alsoWithout = new UnifiedProfileController.TimelineEvent();

        Assert.areEqual(-1, withDate.compareTo(withoutDate));
        Assert.areEqual(1, withoutDate.compareTo(withDate));
        Assert.areEqual(0, withoutDate.compareTo(alsoWithout));

        List<UnifiedProfileController.TimelineEvent> events = new List<UnifiedProfileController.TimelineEvent>{
            withoutDate,
            withDate
        };
        events.sort();
        Assert.isNotNull(events[0].eventDateTime, 'Dated events sort ahead of undated ones');
    }

    @IsTest
    static void theSameActionCodeReadsDifferentlyPerChannel() {
        Assert.areEqual('Email Click', UnifiedProfileController.friendlyAction('CLICK', 'Email'));
        Assert.areEqual('Web Click', UnifiedProfileController.friendlyAction('CLICK', 'Web'));
        Assert.areEqual('Email Open', UnifiedProfileController.friendlyAction('OPENED', 'Email'));
    }

    @IsTest
    static void webTrackingSpellingsLandOnOneLabel() {
        // Connector data sends PAGE_VIEW; the action status column sends "Page View".
        Assert.areEqual('Page View', UnifiedProfileController.friendlyAction('PAGE_VIEW', 'Web'));
        Assert.areEqual('Page View', UnifiedProfileController.friendlyAction('Page View', 'Web'));
        Assert.areEqual('Form Submit', UnifiedProfileController.friendlyAction('Form Submit', 'Web'));
    }

    @IsTest
    static void anUnnamedActionStillSaysWhichChannelItCameFrom() {
        Assert.areEqual('Web Engagement', UnifiedProfileController.friendlyAction(null, 'Web'));
        Assert.areEqual('Engagement', UnifiedProfileController.friendlyAction('', 'Email'));
    }

    // ------------------------------------------------------------------
    // Endpoints against an org with no Data Cloud rows
    // ------------------------------------------------------------------

    @IsTest
    static void theHeaderRendersWhenTheProfileHasNoRows() {
        UnifiedProfileController.ProfileHeader header = UnifiedProfileController.getProfileHeader(
            UNIFIED_ID,
            UNIFIED_DMO
        );

        Assert.areEqual(UNIFIED_ID, header.unifiedId, 'The unified key is passed straight through');
        Assert.areEqual(UNIFIED_DMO, header.rulesetDmo);
        Assert.isNull(header.email);
        Assert.isNull(header.addressLine1, 'No unified address means an empty tile, not a failure');
    }

    @IsTest
    static void eachBreakdownSectionAnswersForAnEmptyProfile() {
        Assert.areEqual(
            'Individuals',
            UnifiedProfileController.getIndividualBreakdown(UNIFIED_ID, UNIFIED_DMO).label
        );

        for (String type : new List<String>{ 'Email', 'Phone', 'Address' }) {
            UnifiedProfileController.BreakdownSection section = UnifiedProfileController.getContactPointBreakdown(
                UNIFIED_ID,
                UNIFIED_DMO,
                type
            );
            Assert.areEqual(0, section.totalCount, type + ' has no contributing records');
            Assert.areEqual(0, section.unifiedValueCount);
        }
    }

    @IsTest
    static void anUnknownContactPointTypeIsTreatedAsEmail() {
        Assert.areEqual(
            'Emails',
            UnifiedProfileController.getContactPointBreakdown(UNIFIED_ID, UNIFIED_DMO, 'carrier pigeon').label
        );
        Assert.areEqual('Emails', UnifiedProfileController.getContactPointBreakdown(UNIFIED_ID, UNIFIED_DMO, null).label);
    }

    @IsTest
    static void bothTimelinesQueryEveryContributingRecord() {
        // The contributing ids are what the timelines fan out over; seeding them takes the
        // endpoints past the early return and through the engagement and order reads.
        UnifiedProfileController.sourceIdCache.put(
            'IndividualIdentityLink__dlm|' + UNIFIED_ID,
            new List<String>{ 'REC-0001', 'REC-0002' }
        );
        UnifiedProfileController.emailAddressCache.put(UNIFIED_ID, new List<String>{ 'a@example.com' });

        Assert.areEqual(0, UnifiedProfileController.getEngagementTimeline(UNIFIED_ID, UNIFIED_DMO, 10).size());
        // The query service is unavailable to a test, which is the same as an org that cannot
        // read Sales Order: an empty panel rather than an error.
        Assert.areEqual(0, UnifiedProfileController.getOrderTimeline(UNIFIED_ID, UNIFIED_DMO, 5).size());
    }

    @IsTest
    static void aProfileAnswersToItsUnifiedIdAndItsContributors() {
        UnifiedProfileController.sourceIdCache.put(
            'IndividualIdentityLink__dlm|' + UNIFIED_ID,
            new List<String>{ 'REC-0001' }
        );

        List<String> ids = UnifiedProfileController.profileIdentifiers(UNIFIED_ID, UNIFIED_DMO);

        Assert.areEqual(2, ids.size());
        Assert.isTrue(new Set<String>(ids).contains(UNIFIED_ID));
        Assert.isTrue(new Set<String>(ids).contains('REC-0001'));
        Assert.areEqual(0, UnifiedProfileController.profileIdentifiers(null, UNIFIED_DMO).size());
    }

    @IsTest
    static void theUnifiedKeyIsSharedWithTheOtherPanels() {
        Assert.areEqual(UNIFIED_ID, UnifiedProfileController.resolveUnifiedIdFor(UNIFIED_ID, UNIFIED_DMO));
        Assert.isNull(UnifiedProfileController.resolveUnifiedIdFor('   ', UNIFIED_DMO));
        // A CDP record page hands over a row id instead, which is looked up once and remembered.
        Assert.isNull(UnifiedProfileController.resolveUnifiedIdFor('0Pp000000000000AAA', UNIFIED_DMO));
        Assert.isNull(UnifiedProfileController.resolveUnifiedIdFor('0Pp000000000000AAA', UNIFIED_DMO));
    }

    // ------------------------------------------------------------------
    // Turning Data Cloud rows into what the page shows
    // ------------------------------------------------------------------

    @IsTest
    static void theHeaderReadsItsNameOffTheUnifiedRecord() {
        Datetime modified = Datetime.newInstanceGmt(2026, 7, 30, 9, 15, 0);
        UnifiedProfileController.ProfileHeader header = new UnifiedProfileController.ProfileHeader();

        UnifiedProfileController.applyIdentity(
            header,
            new Map<String, Object>{
                'ssot__FirstName__c' => 'Ravi',
                'ssot__LastName__c' => 'Nair',
                'ssot__PersonName__c' => 'Ravi Nair',
                'ssot__LastModifiedDate__c' => modified
            }
        );

        Assert.areEqual('Ravi', header.firstName);
        Assert.areEqual('Ravi Nair', header.personName);
        Assert.areEqual(modified, header.lastModified);
    }

    @IsTest
    static void theContactPointKeyedToTheProfileIsTheAttributedOne() {
        List<Map<String, Object>> rows = new List<Map<String, Object>>{
            new Map<String, Object>{ 'ssot__Id__c' => 'other', 'ssot__EmailAddress__c' => 'b@example.com' },
            new Map<String, Object>{ 'ssot__Id__c' => UNIFIED_ID, 'ssot__EmailAddress__c' => 'a@example.com' }
        };

        Assert.areEqual(
            'a@example.com',
            UnifiedProfileController.renderContactPoint(
                UnifiedProfileController.attributedContactPoint(rows, UNIFIED_ID, 'email'),
                'email'
            )
        );
        Assert.isNull(
            UnifiedProfileController.attributedContactPoint(rows, 'not-on-this-profile', 'email'),
            'No contact point carries that key'
        );
    }

    @IsTest
    static void anAttributedContactPointWithNothingMappedDoesNotWin() {
        List<Map<String, Object>> rows = new List<Map<String, Object>>{
            new Map<String, Object>{ 'ssot__Id__c' => UNIFIED_ID, 'ssot__EmailAddress__c' => '' }
        };

        Assert.isNull(UnifiedProfileController.attributedContactPoint(rows, UNIFIED_ID, 'email'));
    }

    @IsTest
    static void theValueTheMostRecordsAgreedOnLeadsTheTile() {
        List<Map<String, Object>> rows = new List<Map<String, Object>>{
            new Map<String, Object>{ 'ssot__Id__c' => 'cp-1', 'ssot__TelephoneNumber__c' => '+91 90000 11111' },
            new Map<String, Object>{ 'ssot__Id__c' => 'cp-2', 'ssot__TelephoneNumber__c' => '+91 90000 22222' }
        };
        Map<String, Integer> counts = new Map<String, Integer>{ 'cp-1' => 1, 'cp-2' => 3 };

        Map<String, Object> picked = UnifiedProfileController.pickContactPoint(rows, counts, UNIFIED_ID, 'phone');

        Assert.areEqual('+91 90000 22222', UnifiedProfileController.renderContactPoint(picked, 'phone'));
        Assert.areEqual(new List<String>{ 'cp-1', 'cp-2' }, sorted(UnifiedProfileController.idsOf(rows)));
    }

    @IsTest
    static void aSourceRecordCountsOnceHoweverOftenTheRulesetRelinksIt() {
        Map<String, Integer> counts = UnifiedProfileController.countLinks(
            new List<Map<String, Object>>{
                link('REC-0001', 'cp-1'),
                link('REC-0001', 'cp-1'),
                link('REC-0002', 'cp-1'),
                link('REC-0003', 'cp-2'),
                link('', 'cp-2')
            }
        );

        Assert.areEqual(2, counts.get('cp-1'), 'The repeated link row is the same contribution');
        Assert.areEqual(1, counts.get('cp-2'));
    }

    @IsTest
    static void contributingIndividualsAreNamedFromTheirSourceRecords() {
        Datetime joined = Datetime.newInstanceGmt(2026, 6, 25, 12, 0, 0);
        Map<String, UnifiedProfileController.SourceRow> byId = UnifiedProfileController.contributingIndividuals(
            new List<Map<String, Object>>{
                new Map<String, Object>{
                    'SourceRecordId__c' => 'REC-0001',
                    'ssot__DataSourceId__c' => 'Loyalty',
                    'CreatedDate__c' => joined
                },
                new Map<String, Object>{
                    'SourceRecordId__c' => 'REC-0001',
                    'CreatedDate__c' => joined.addDays(4)
                },
                new Map<String, Object>{ 'SourceRecordId__c' => '' }
            }
        );

        Assert.areEqual(1, byId.size(), 'A relinked record is one contributor');
        Assert.areEqual(joined, byId.get('REC-0001').createdDate, 'Dated from when it joined the profile');

        UnifiedProfileController.applyIndividualNames(
            byId,
            new List<Map<String, Object>>{
                new Map<String, Object>{ 'ssot__Id__c' => 'REC-0001', 'ssot__PersonName__c' => 'Ravi Nair' },
                new Map<String, Object>{ 'ssot__Id__c' => 'NOT-LINKED', 'ssot__PersonName__c' => 'Someone Else' }
            }
        );

        Assert.areEqual('Ravi Nair', byId.get('REC-0001').value);
    }

    @IsTest
    static void aSectionListsEveryContributorAndBadgesOneWinner() {
        // Two unified emails on one profile. The attributed record decides the winner inside the
        // primary value, and the runner-up value's contributor is listed without being flagged.
        Datetime base = Datetime.newInstanceGmt(2026, 6, 25, 12, 0, 0);
        UnifiedProfileController.BreakdownSection section = new UnifiedProfileController.BreakdownSection();

        UnifiedProfileController.fillContactSection(
            section,
            new Map<String, String>{ UNIFIED_ID => 'a@example.com', 'cp-2' => 'b@example.com' },
            new List<Map<String, Object>>{
                dated(link('REC-0001', UNIFIED_ID), base),
                dated(link('REC-0002', UNIFIED_ID), base.addDays(3)),
                dated(link('REC-0003', 'cp-2'), base.addDays(9))
            },
            new Map<String, List<String>>{
                'REC-0001' => new List<String>{ 'a@example.com' },
                'REC-0002' => new List<String>{ 'a@example.com' },
                'REC-0003' => new List<String>{ 'b@example.com' }
            },
            UNIFIED_ID,
            'REC-0001'
        );

        Assert.areEqual(3, section.totalCount, 'Every contributing record is listed');
        Assert.areEqual('a@example.com', section.winnerValue, 'The attributed unified value leads');
        Assert.isTrue(section.rows[0].isWinner);
        Assert.isTrue(section.rows[1].matchesWinner);
        Assert.isFalse(section.rows[2].isWinner, 'The second email has no winner of its own');
        Assert.areEqual(
            'The unified record is attributed to this source record by the ruleset.',
            section.winnerBasis
        );
    }

    @IsTest
    static void oneRecordSupplyingTwoValuesIsListedAgainstEach() {
        Datetime base = Datetime.newInstanceGmt(2026, 6, 25, 12, 0, 0);
        UnifiedProfileController.BreakdownSection section = new UnifiedProfileController.BreakdownSection();

        UnifiedProfileController.fillContactSection(
            section,
            new Map<String, String>{ UNIFIED_ID => 'work@example.com', 'cp-2' => 'home@example.com' },
            new List<Map<String, Object>>{
                dated(link('REC-0001', UNIFIED_ID), base),
                dated(link('REC-0001', 'cp-2'), base)
            },
            new Map<String, List<String>>{
                'REC-0001' => new List<String>{ 'home@example.com', 'work@example.com' }
            },
            UNIFIED_ID,
            null
        );

        Assert.areEqual(2, section.totalCount);
        Assert.areEqual('work@example.com', section.rows[0].value, 'Each row shows the value its link points at');
        Assert.areEqual('home@example.com', section.rows[1].value);
    }

    @IsTest
    static void contactValuesAreKeyedTheWayTheLinksPointAtThem() {
        Assert.areEqual(
            new Map<String, String>{ 'cp-1' => '146 Market St, San Francisco' },
            UnifiedProfileController.unifiedContactValues(
                new List<Map<String, Object>>{
                    new Map<String, Object>{
                        'ssot__Id__c' => 'cp-1',
                        'ssot__AddressLine1__c' => '146 Market St',
                        'ssot__CityName__c' => 'San Francisco'
                    },
                    new Map<String, Object>{ 'ssot__AddressLine1__c' => 'no id, no use' }
                },
                'address'
            )
        );

        Map<String, List<String>> bySource = UnifiedProfileController.sourceContactValues(
            new List<Map<String, Object>>{
                new Map<String, Object>{ 'ssot__Id__c' => 'REC-1', 'ssot__EmailAddress__c' => 'a@example.com' },
                new Map<String, Object>{ 'ssot__Id__c' => 'REC-1', 'ssot__EmailAddress__c' => 'b@example.com' }
            },
            'email'
        );
        Assert.areEqual(2, bySource.get('REC-1').size(), 'Both of the record\'s addresses are kept');

        Assert.areEqual(
            new List<String>{ 'REC-1' },
            UnifiedProfileController.contributingSourceIds(
                new List<Map<String, Object>>{ link('REC-1', 'cp-1'), link('REC-1', 'cp-2'), link('', 'cp-2') }
            )
        );
    }

    @IsTest
    static void aValueIsRenderedTheWayItsOwnTypeReads() {
        Map<String, Object> row = new Map<String, Object>{
            'ssot__EmailAddress__c' => 'a@example.com',
            'ssot__TelephoneNumber__c' => '+91 90000 11111',
            'ssot__AddressLine1__c' => '146 Market St',
            'ssot__CityName__c' => 'San Francisco',
            'ssot__StateProvinceName__c' => 'California',
            'ssot__PostalCodeText__c' => '94105'
        };

        Assert.areEqual('a@example.com', UnifiedProfileController.renderContactPoint(row, 'email'));
        Assert.areEqual('+91 90000 11111', UnifiedProfileController.renderContactPoint(row, 'phone'));
        Assert.areEqual(
            '146 Market St, San Francisco, California, 94105',
            UnifiedProfileController.renderContactPoint(row, 'address')
        );
    }

    @IsTest
    static void theLinkedValueIsPreferredOverTheRecordsOther() {
        Assert.areEqual(
            'work@example.com',
            UnifiedProfileController.pickSourceValue(
                new List<String>{ 'home@example.com', 'work@example.com' },
                'WORK@example.com'
            ),
            'Matched without regard to case'
        );
        Assert.areEqual(
            'home@example.com',
            UnifiedProfileController.pickSourceValue(new List<String>{ 'home@example.com' }, 'nothing matches')
        );
        Assert.isNull(UnifiedProfileController.pickSourceValue(null, 'a@example.com'));
        Assert.isNull(UnifiedProfileController.pickSourceValue(new List<String>(), 'a@example.com'));
    }

    @IsTest
    static void aNameIsBuiltFromWhicheverPartsTheSourceFilled() {
        Assert.areEqual('Ravi Nair', UnifiedProfileController.displayName('Ravi Nair', 'Ravi', 'Nair'));
        Assert.areEqual('Ravi Nair', UnifiedProfileController.displayName(null, 'Ravi', 'Nair'));
        // Several systems put the whole name in both parts.
        Assert.areEqual('Ravi Nair', UnifiedProfileController.displayName(null, 'Ravi Nair', 'Ravi Nair'));
        Assert.areEqual('Ravi', UnifiedProfileController.displayName(null, 'Ravi', null));
        Assert.areEqual('Nair', UnifiedProfileController.displayName(null, null, 'Nair'));
    }

    // ------------------------------------------------------------------
    // Engagement timeline
    // ------------------------------------------------------------------

    @IsTest
    static void aConnectorEmailEventNamesItsBulkMessage() {
        List<UnifiedProfileController.TimelineEvent> events = new List<UnifiedProfileController.TimelineEvent>();
        Set<String> seen = new Set<String>();
        Set<String> bulkIds = new Set<String>();
        Datetime opened = Datetime.newInstanceGmt(2026, 7, 20, 6, 30, 0);

        UnifiedProfileController.addEmailEvent(
            events,
            seen,
            bulkIds,
            new Map<String, Object>{
                'ssot__Id__c' => 'EE-1',
                'ssot__IndividualId__c' => 'REC-0001',
                'ssot__EngagementDateTm__c' => opened,
                'ssot__EngagementChannelActionId__c' => 'OPEN',
                'ssot__BulkEmailMessageId__c' => 'BEM-9',
                'ssot__LinkName__c' => 'Spring offer'
            }
        );

        Assert.areEqual(1, events.size());
        Assert.areEqual('Email Open', events[0].eventType);
        Assert.areEqual('utility:preview', events[0].iconName);
        Assert.areEqual('BEM-9', events[0].campaignName, 'The id stands in until the name is read');
        Assert.areEqual(opened, events[0].eventDateTime);
        Assert.isTrue(bulkIds.contains('BEM-9'));

        UnifiedProfileController.applyCampaignNames(
            events,
            new Map<String, String>{ 'BEM-9' => 'Spring Sale 2026' }
        );
        Assert.areEqual('Spring Sale 2026', events[0].campaignName);
    }

    @IsTest
    static void anUploadedEmailEventReadsTheSameWayOnTheTimeline() {
        // A file load names the engagement type and carries the email's own name instead.
        List<UnifiedProfileController.TimelineEvent> events = new List<UnifiedProfileController.TimelineEvent>();
        Set<String> seen = new Set<String>();
        Set<String> bulkIds = new Set<String>();

        UnifiedProfileController.addEmailEvent(
            events,
            seen,
            bulkIds,
            new Map<String, Object>{
                'ssot__Id__c' => 'EE-2',
                'ssot__EngagementTypeId__c' => 'CLICKED',
                'ssot__EmailName__c' => 'Welcome Journey'
            }
        );
        // The same row reached by the address query as well as the individual one.
        UnifiedProfileController.addEmailEvent(
            events,
            seen,
            bulkIds,
            new Map<String, Object>{ 'ssot__Id__c' => 'EE-2', 'ssot__EngagementTypeId__c' => 'CLICKED' }
        );

        Assert.areEqual(1, events.size(), 'A row found by both queries is one event');
        Assert.areEqual('Email Click', events[0].eventType);
        Assert.areEqual('utility:link', events[0].iconName);
        Assert.areEqual('Welcome Journey', events[0].campaignName);
        Assert.isTrue(bulkIds.isEmpty());
    }

    @IsTest
    static void aWebEventShowsThePageItHappenedOn() {
        UnifiedProfileController.TimelineEvent titled = UnifiedProfileController.webEvent(
            new Map<String, Object>{
                'ssot__Id__c' => 'WE-1',
                'ssot__EngmtChannelActionStatus__c' => 'Page View',
                'ssot__UtmCampaignName__c' => 'summer_launch',
                'ssot__PagePublicTitleName__c' => 'Pricing',
                'ssot__PageURL__c' => 'https://example.com/pricing'
            }
        );

        Assert.areEqual('Web', titled.channel);
        Assert.areEqual('Page View', titled.eventType);
        Assert.areEqual('Pricing', titled.detail);
        Assert.areEqual('summer_launch', titled.campaignName);

        UnifiedProfileController.TimelineEvent untitled = UnifiedProfileController.webEvent(
            new Map<String, Object>{ 'ssot__PageURL__c' => 'https://example.com/pricing' }
        );
        Assert.areEqual('https://example.com/pricing', untitled.detail, 'The URL stands in for a missing title');
        Assert.areEqual('Web Engagement', untitled.eventType);
    }

    @IsTest
    static void whicheverColumnTheSourceFilledSaysWhatTheVisitorDid() {
        Assert.areEqual(
            'CLICK',
            UnifiedProfileController.webAction(
                new Map<String, Object>{
                    'ssot__EngagementChannelActionId__c' => 'CLICK',
                    'ssot__EngmtChannelActionStatus__c' => 'Page View'
                }
            )
        );
        Assert.areEqual(
            'Page View',
            UnifiedProfileController.webAction(new Map<String, Object>{ 'ssot__EngmtChannelActionStatus__c' => 'Page View' })
        );
        Assert.areEqual(
            'FORM_SUBMIT',
            UnifiedProfileController.webAction(new Map<String, Object>{ 'ssot__EngagementTypeId__c' => 'FORM_SUBMIT' })
        );
        Assert.isNull(UnifiedProfileController.webAction(new Map<String, Object>()));
    }

    @IsTest
    static void anActionWithoutAnIconStillGetsTheChannelOne() {
        Assert.areEqual('utility:warning', UnifiedProfileController.emailIcon('BOUNCED'));
        Assert.areEqual('utility:ban', UnifiedProfileController.emailIcon('UNSUBSCRIBED'));
        Assert.areEqual('utility:email', UnifiedProfileController.emailIcon(null));
        Assert.areEqual('Email Sent', UnifiedProfileController.friendlyAction('SEND_STATUS', 'Email'));
        Assert.areEqual('Email Bounce', UnifiedProfileController.friendlyAction('BOUNCE', 'Email'));
        Assert.areEqual('Unsubscribed', UnifiedProfileController.friendlyAction('UNSUBSCRIBE', 'Email'));
    }

    @IsTest
    static void theTimelineShowsNoMoreThanItWasAskedFor() {
        List<UnifiedProfileController.TimelineEvent> events = new List<UnifiedProfileController.TimelineEvent>();
        for (Integer i = 0; i < 5; i++) {
            events.add(new UnifiedProfileController.TimelineEvent());
        }

        Assert.areEqual(3, UnifiedProfileController.trimTo(events, 3).size());
        Assert.areEqual(5, UnifiedProfileController.trimTo(events, 25).size());
        Assert.areEqual(25, UnifiedProfileController.boundRows(null), 'The panel asks for 25 by default');
        Assert.areEqual(25, UnifiedProfileController.boundRows(0));
        Assert.areEqual(50, UnifiedProfileController.boundRows(50));
        Assert.areEqual(200, UnifiedProfileController.boundRows(5000), 'However many are asked for, 200 is the cap');
    }

    // ------------------------------------------------------------------
    // Sales orders, read through the query service
    // ------------------------------------------------------------------

    private static UnifiedProfileController.CdpRows salesOrderRows(List<Object> row) {
        UnifiedProfileController.CdpRows result = new UnifiedProfileController.CdpRows();
        result.index = new Map<String, Integer>{
            'ssot__OrderNumber__c' => 0,
            'ssot__SoldToCustomerId__c' => 1,
            'ssot__SalesOrderStatusId__c' => 2,
            'ssot__CurrencyCode__c' => 3,
            'ssot__OrderStartDate__c' => 4,
            'ssot__GrandTotalAmount__c' => 5,
            'ssot__TotalProductAmount__c' => 6,
            'ssot__TotalTaxAmount__c' => 7
        };
        result.rows = new List<List<Object>>{ row };
        return result;
    }

    @IsTest
    static void anOrderReadsItsTotalAndTheDayItWasPlaced() {
        UnifiedProfileController.CdpRows result = salesOrderRows(
            new List<Object>{
                'SO-1001',
                'REC-0001',
                'Fulfilled',
                'USD',
                '2026-04-21 00:00:00.000 UTC',
                '1289.9900',
                null,
                null
            }
        );

        List<UnifiedProfileController.OrderRow> orders = UnifiedProfileController.orderRows(result);

        Assert.areEqual(1, orders.size());
        Assert.areEqual('SO-1001', orders[0].orderNumber);
        Assert.areEqual('REC-0001', orders[0].customerId);
        Assert.areEqual('Fulfilled', orders[0].status);
        Assert.areEqual('USD', orders[0].currencyCode);
        Assert.areEqual(Date.newInstance(2026, 4, 21), orders[0].orderDate);
        Assert.areEqual(1289.99, orders[0].totalAmount);
    }

    @IsTest
    static void anOrderWithoutAGrandTotalAddsUpWhatItHas() {
        UnifiedProfileController.CdpRows result = salesOrderRows(
            new List<Object>{ 'SO-1002', 'REC-0001', null, 'INR', null, null, '1000.00', '180.00' }
        );

        List<UnifiedProfileController.OrderRow> orders = UnifiedProfileController.orderRows(result);
        Assert.areEqual(1180.00, orders[0].totalAmount, 'Product plus tax stands in for the grand total');
        Assert.isNull(orders[0].orderDate, 'No mapped date leaves the order undated');

        UnifiedProfileController.CdpRows unmapped = salesOrderRows(
            new List<Object>{ 'SO-1003', 'REC-0001', null, null, null, null, null, null }
        );
        Assert.isNull(
            UnifiedProfileController.orderRows(unmapped)[0].totalAmount,
            'An unmapped amount is not a zero'
        );
    }

    @IsTest
    static void ordersReadFromTheQueryServiceAreCleanedUp() {
        UnifiedProfileController.CdpRows result = salesOrderRows(new List<Object>{ 'SO-1004' });

        Assert.isNull(result.text(new List<Object>{ 'SO-1004' }, 'ssot__CurrencyCode__c'), 'A column past the row end');
        Assert.isNull(result.text(new List<Object>{ 'SO-1004' }, 'not_a_column__c'));
        Assert.isNull(result.number(new List<Object>{ 'not a number' }, 'ssot__OrderNumber__c'));
        Assert.isNull(result.dateOf(new List<Object>{ 'short' }, 'ssot__OrderNumber__c'));
        Assert.isNull(result.dateOf(new List<Object>{ 'not-a-date-at-all' }, 'ssot__OrderNumber__c'));
    }

    @IsTest
    static void ordersSortNewestFirstWithUndatedOnesLast() {
        UnifiedProfileController.OrderRow april = new UnifiedProfileController.OrderRow();
        april.orderDate = Date.newInstance(2026, 4, 21);
        UnifiedProfileController.OrderRow june = new UnifiedProfileController.OrderRow();
        june.orderDate = Date.newInstance(2026, 6, 2);
        UnifiedProfileController.OrderRow undated = new UnifiedProfileController.OrderRow();

        List<UnifiedProfileController.OrderRow> orders = new List<UnifiedProfileController.OrderRow>{
            april,
            undated,
            june
        };
        orders.sort();

        Assert.areEqual(june.orderDate, orders[0].orderDate);
        Assert.areEqual(april.orderDate, orders[1].orderDate);
        Assert.isNull(orders[2].orderDate);
        Assert.areEqual(0, april.compareTo(april));
    }

    @IsTest
    static void anUnmappedColumnIsNamedSoTheQueryCanBeRetriedWithoutIt() {
        Assert.areEqual(
            'ssot__GrandTotalAmount__c',
            UnifiedProfileController.unmappedColumn(
                'Failed to execute query: unknown column \'ssot__GrandTotalAmount__c\' in the table'
            )
        );
        Assert.isNull(UnifiedProfileController.unmappedColumn('some other failure'));
        Assert.isNull(UnifiedProfileController.unmappedColumn(null));
    }

    // ------------------------------------------------------------------

    private static Map<String, Object> link(String sourceId, String unifiedCpId) {
        return new Map<String, Object>{ 'SourceRecordId__c' => sourceId, 'UnifiedRecordId__c' => unifiedCpId };
    }

    private static Map<String, Object> dated(Map<String, Object> row, Datetime created) {
        row.put('CreatedDate__c', created);
        row.put('ssot__DataSourceId__c', 'Loyalty');
        return row;
    }

    private static List<String> sorted(List<String> values) {
        values.sort();
        return values;
    }
}
