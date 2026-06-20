@isTest
private class ListQuoteLineGroupsTest {

    @testSetup
    static void setup() {
        // QuoteLineItem requires a PricebookEntry in this org, so set up the standard
        // pricebook chain and link the quote to it.
        Product2 p = new Product2(Name = 'QuantumBit Complete Solution', IsActive = true);
        insert p;
        Id stdPb = Test.getStandardPricebookId();
        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = stdPb, Product2Id = p.Id, UnitPrice = 100, IsActive = true);
        insert pbe;

        Quote q = new Quote(Name = 'List Groups Test Quote', Pricebook2Id = stdPb);
        insert q;

        QuoteLineGroup ca = new QuoteLineGroup(Name = 'GEO #2 - CALIFORNIA', QuoteId = q.Id, SortOrder = 1);
        QuoteLineGroup ny = new QuoteLineGroup(Name = 'GEO #1 - NEW YORK', QuoteId = q.Id, SortOrder = 2);
        insert new List<QuoteLineGroup>{ ca, ny };
        insert new List<QuoteLineGroup>{
            new QuoteLineGroup(Name = 'LOS ANGELES', QuoteId = q.Id, ParentQuoteLineGroupId = ca.Id, SortOrder = 3)
        };

        // One line item directly in New York so a non-zero bundleCount is exercised.
        insert new QuoteLineItem(
            QuoteId = q.Id, Product2Id = p.Id, PricebookEntryId = pbe.Id,
            Quantity = 1, UnitPrice = 100, QuoteLineGroupId = ny.Id
        );
    }

    private static Id quoteId() {
        return [SELECT Id FROM Quote WHERE Name = 'List Groups Test Quote' LIMIT 1].Id;
    }

    @isTest
    static void testBlankQuoteIdFails() {
        ListQuoteLineGroups.Request req = new ListQuoteLineGroups.Request();
        req.quoteId = '';
        List<ListQuoteLineGroups.Result> res =
            ListQuoteLineGroups.execute(new List<ListQuoteLineGroups.Request>{ req });
        System.assertEquals(false, res[0].isSuccess);
        System.assertNotEquals(null, res[0].errorMessage);
    }

    @isTest
    static void testListsHierarchyWithCounts() {
        ListQuoteLineGroups.Request req = new ListQuoteLineGroups.Request();
        req.quoteId = quoteId();
        List<ListQuoteLineGroups.Result> res =
            ListQuoteLineGroups.execute(new List<ListQuoteLineGroups.Request>{ req });

        System.assertEquals(true, res[0].isSuccess);
        System.assertEquals(3, res[0].groupCount, 'CA + NY + LA');

        List<Object> groups = (List<Object>) JSON.deserializeUntyped(res[0].groupsJson);
        Boolean sawSubgroup = false;
        Boolean sawNyWithCount = false;
        for (Object o : groups) {
            Map<String, Object> g = (Map<String, Object>) o;
            if (g.get('name') == 'LOS ANGELES') {
                sawSubgroup = true;
                System.assertEquals(true, g.get('isSubgroup'));
                System.assertEquals('GEO #2 - CALIFORNIA', g.get('parentName'));
            }
            if (g.get('name') == 'GEO #1 - NEW YORK') {
                sawNyWithCount = true;
                System.assertEquals(1, (Integer) g.get('bundleCount'));
                System.assertEquals(false, g.get('isSubgroup'));
            }
        }
        System.assert(sawSubgroup, 'LA subgroup should appear with parentName + isSubgroup');
        System.assert(sawNyWithCount, 'NY should report bundleCount 1');
    }
}
