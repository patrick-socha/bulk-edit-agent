@isTest
private class QuoteLineGroupScopeTest {

    // Builds a quote with the real-world shape:
    //   GEO #1 - NEW YORK            (root)
    //   GEO #2 - CALIFORNIA          (root)
    //     ├─ LOS ANGELES             (subgroup)
    //     └─ SAN FRANCISCO           (subgroup)
    //   GEO #3 - TEXAS               (root)
    //     ├─ AUSTIN, DALLAS, HOUSTON (subgroups)
    @testSetup
    static void setup() {
        Quote q = new Quote(Name = 'Group Scope Test Quote');
        insert q;

        QuoteLineGroup ny = new QuoteLineGroup(Name = 'GEO #1 - NEW YORK', QuoteId = q.Id);
        QuoteLineGroup ca = new QuoteLineGroup(Name = 'GEO #2 - CALIFORNIA', QuoteId = q.Id);
        QuoteLineGroup tx = new QuoteLineGroup(Name = 'GEO #3 - TEXAS', QuoteId = q.Id);
        insert new List<QuoteLineGroup>{ ny, ca, tx };

        insert new List<QuoteLineGroup>{
            new QuoteLineGroup(Name = 'LOS ANGELES', QuoteId = q.Id, ParentQuoteLineGroupId = ca.Id),
            new QuoteLineGroup(Name = 'SAN FRANCISCO', QuoteId = q.Id, ParentQuoteLineGroupId = ca.Id),
            new QuoteLineGroup(Name = 'AUSTIN', QuoteId = q.Id, ParentQuoteLineGroupId = tx.Id),
            new QuoteLineGroup(Name = 'DALLAS', QuoteId = q.Id, ParentQuoteLineGroupId = tx.Id),
            new QuoteLineGroup(Name = 'HOUSTON', QuoteId = q.Id, ParentQuoteLineGroupId = tx.Id)
        };
    }

    private static Id quoteId() {
        return [SELECT Id FROM Quote WHERE Name = 'Group Scope Test Quote' LIMIT 1].Id;
    }

    private static Id groupId(String name) {
        return [SELECT Id FROM QuoteLineGroup WHERE Name = :name LIMIT 1].Id;
    }

    @isTest
    static void testBlankIsNotScoping() {
        QuoteLineGroupScope.ScopeResult r = QuoteLineGroupScope.resolveFromCsv(quoteId(), '');
        System.assertEquals(false, r.scopingRequested, 'Blank input must mean whole-quote');
        System.assert(r.groupIds.isEmpty());

        QuoteLineGroupScope.ScopeResult r2 = QuoteLineGroupScope.resolveFromCsv(quoteId(), null);
        System.assertEquals(false, r2.scopingRequested);
    }

    @isTest
    static void testExactNormalizedMatch() {
        // Full canonical name (exact after normalize) binds precisely to one root.
        QuoteLineGroupScope.ScopeResult r =
            QuoteLineGroupScope.resolveFromCsv(quoteId(), 'GEO #1 - NEW YORK');
        System.assertEquals(true, r.scopingRequested);
        System.assertEquals(1, r.matchedGroupNames.size());
        System.assertEquals('GEO #1 - NEW YORK', r.matchedGroupNames[0]);
        System.assert(r.groupIds.contains(groupId('GEO #1 - NEW YORK')));
        // NY has no subgroups -> just itself.
        System.assertEquals(1, r.groupIds.size());
    }

    @isTest
    static void testCasualContainsMatch() {
        // "california" is not exact, falls back to substring against "GEO #2 - CALIFORNIA".
        QuoteLineGroupScope.ScopeResult r =
            QuoteLineGroupScope.resolveFromCsv(quoteId(), 'california');
        System.assertEquals(true, r.scopingRequested);
        System.assert(r.matchedGroupNames.contains('GEO #2 - CALIFORNIA'));
        System.assertEquals(0, r.unmatchedTokens.size());
    }

    @isTest
    static void testSubgroupDescendantExpansion() {
        // Matching California MUST pull in LA + SF (the headline behavior).
        QuoteLineGroupScope.ScopeResult r =
            QuoteLineGroupScope.resolveFromCsv(quoteId(), 'California');
        System.assert(r.groupIds.contains(groupId('GEO #2 - CALIFORNIA')));
        System.assert(r.groupIds.contains(groupId('LOS ANGELES')), 'LA subgroup must be included');
        System.assert(r.groupIds.contains(groupId('SAN FRANCISCO')), 'SF subgroup must be included');
        System.assertEquals(3, r.groupIds.size(), 'CA + its 2 subgroups');
        System.assert(r.scopeDescription.contains('LOS ANGELES'));
        // And it must NOT bleed into Texas.
        System.assert(!r.groupIds.contains(groupId('GEO #3 - TEXAS')));
    }

    @isTest
    static void testDirectSubgroupMatch() {
        // Naming a subgroup directly scopes to just that subgroup.
        QuoteLineGroupScope.ScopeResult r =
            QuoteLineGroupScope.resolveFromCsv(quoteId(), 'Austin');
        System.assertEquals(1, r.groupIds.size());
        System.assert(r.groupIds.contains(groupId('AUSTIN')));
    }

    @isTest
    static void testMultipleTokens() {
        QuoteLineGroupScope.ScopeResult r =
            QuoteLineGroupScope.resolveFromCsv(quoteId(), 'California, New York');
        // CA(+LA+SF) + NY = 4 groups.
        System.assertEquals(4, r.groupIds.size());
        System.assert(r.groupIds.contains(groupId('GEO #1 - NEW YORK')));
        System.assert(r.groupIds.contains(groupId('LOS ANGELES')));
        System.assert(!r.groupIds.contains(groupId('GEO #3 - TEXAS')), 'Texas untouched by omission');
    }

    @isTest
    static void testOverMatchToken() {
        // "geo" substring-matches all three roots -> count 3, and pulls every subtree.
        QuoteLineGroupScope.ScopeResult r =
            QuoteLineGroupScope.resolveFromCsv(quoteId(), 'geo');
        System.assertEquals(3, r.tokenMatchCounts.get('geo'), '"geo" matches all three regions');
        // 3 roots + 5 subgroups = 8 total.
        System.assertEquals(8, r.groupIds.size());
    }

    @isTest
    static void testUnmatchedToken() {
        QuoteLineGroupScope.ScopeResult r =
            QuoteLineGroupScope.resolveFromCsv(quoteId(), 'Florida');
        System.assertEquals(1, r.unmatchedTokens.size());
        System.assertEquals('Florida', r.unmatchedTokens[0]);
        System.assert(r.availableGroupNames.contains('GEO #1 - NEW YORK'),
            'availableGroupNames should list real groups for error messaging');
    }

    @isTest
    static void testMixedMatchedAndUnmatched() {
        // One good token, one typo: the good one still resolves; the typo is reported.
        QuoteLineGroupScope.ScopeResult r =
            QuoteLineGroupScope.resolveFromCsv(quoteId(), 'New York, Texass');
        System.assert(r.groupIds.contains(groupId('GEO #1 - NEW YORK')));
        System.assertEquals(1, r.unmatchedTokens.size());
        System.assertEquals('Texass', r.unmatchedTokens[0]);
        // Caller (the bulk class) is responsible for failing the whole request on any unmatched token.
    }

    @isTest
    static void testSplitNames() {
        List<String> parts = QuoteLineGroupScope.splitNames(' California , , New York ,');
        System.assertEquals(2, parts.size(), 'blank/empty tokens dropped, rest trimmed');
        System.assertEquals('California', parts[0]);
        System.assertEquals('New York', parts[1]);
    }
}
