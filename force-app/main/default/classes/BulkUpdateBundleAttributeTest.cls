@isTest
private class BulkUpdateBundleAttributeTest {

    private class SuccessMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse resp = new HttpResponse();
            resp.setStatusCode(201);
            if (req.getEndpoint().contains('load-instance')) {
                resp.setBody('{"success":true,"contextId":"ctx_test"}');
            } else if (req.getEndpoint().contains('save-instance')) {
                resp.setBody('{"success":true,"errors":[]}');
            } else {
                resp.setBody('{"success":true,"errors":[],"configuratorMessages":{}}');
            }
            return resp;
        }
    }

    @isTest
    static void testMissingInputs() {
        BulkUpdateBundleAttribute.Request req = new BulkUpdateBundleAttribute.Request();
        req.quoteId = '0Q0000000000001AAA';
        // missing bundleProductId / attributeName / desiredValue
        List<BulkUpdateBundleAttribute.Result> res =
            BulkUpdateBundleAttribute.execute(new List<BulkUpdateBundleAttribute.Request>{ req });
        System.assertEquals(false, res[0].isSuccess);
        System.assertNotEquals(null, res[0].errorMessage);
    }

    @isTest
    static void testNoInstancesFound() {
        Test.setMock(HttpCalloutMock.class, new SuccessMock());
        BulkUpdateBundleAttribute.Request req = new BulkUpdateBundleAttribute.Request();
        req.quoteId = '0Q0000000000123AAA';
        req.bundleProductId = '01t000000000123AAA';
        req.attributeName = 'Operating System';
        req.desiredValue = 'Redhat Enterprise Linux';
        List<BulkUpdateBundleAttribute.Result> res =
            BulkUpdateBundleAttribute.execute(new List<BulkUpdateBundleAttribute.Request>{ req });
        System.assertEquals(false, res[0].isSuccess);
        System.assertEquals(0, res[0].totalBundles);
        System.assert(res[0].errorMessage.contains('No instances'));
    }

    @isTest
    static void testBuildUpdateNodeShape() {
        // Exercise the shared util's update-node builder for both attribute kinds.
        Map<String, Object> pick = ConfiguratorClient.buildUpdateAttributeNode(
            '0Q0000000000001AAA', '0QL000000000001AAA', '0zu000000000001AAA',
            'AttributePicklistValue', '0v6000000000001AAA');
        List<Object> path = (List<Object>) pick.get('path');
        System.assertEquals(3, path.size(), 'attribute path must be 3 segments');
        Map<String, Object> upd = (Map<String, Object>) pick.get('updatedAttributes');
        System.assert(upd.containsKey('AttributePicklistValue'));

        Map<String, Object> text = ConfiguratorClient.buildUpdateAttributeNode(
            '0Q0000000000001AAA', '0QL000000000001AAA', '0zu000000000001AAA',
            'AttributeValue', '8');
        Map<String, Object> updT = (Map<String, Object>) text.get('updatedAttributes');
        System.assertEquals('8', updT.get('AttributeValue'));
    }

    // ── Group-scoping tests ──────────────────────────────────────────────
    @isTest
    static void testScopedUnmatchedGroupFailsWithoutCallout() {
        TestData td = makeGroupedQuote();
        // No mock: any callout would throw, proving the unmatched-group failure is callout-free.
        BulkUpdateBundleAttribute.Request req = new BulkUpdateBundleAttribute.Request();
        req.quoteId = td.quoteId;
        req.bundleProductId = td.bundleProductId;
        req.attributeName = 'Operating System';
        req.desiredValue = 'Redhat Enterprise Linux';
        req.groupNames = 'Florida';
        List<BulkUpdateBundleAttribute.Result> res =
            BulkUpdateBundleAttribute.execute(new List<BulkUpdateBundleAttribute.Request>{ req });
        System.assertEquals(false, res[0].isSuccess);
        System.assert(res[0].errorMessage.contains('not found'), res[0].errorMessage);
        System.assert(res[0].errorMessage.contains('GEO #1 - NEW YORK'), res[0].errorMessage);
    }

    @isTest
    static void testScopedToCaliforniaIncludesSubgroup() {
        TestData td = makeGroupedQuote();
        Test.setMock(HttpCalloutMock.class, new SuccessMock());
        BulkUpdateBundleAttribute.Request req = new BulkUpdateBundleAttribute.Request();
        req.quoteId = td.quoteId;
        req.bundleProductId = td.bundleProductId;
        req.attributeName = 'Operating System';      // no QLIA rows -> not-found path, but AFTER scoping
        req.desiredValue = 'Redhat Enterprise Linux';
        req.groupNames = 'California';
        List<BulkUpdateBundleAttribute.Result> res =
            BulkUpdateBundleAttribute.execute(new List<BulkUpdateBundleAttribute.Request>{ req });
        // Scoping resolved to California + its subgroups (so the LA bundle is in scope) and
        // reported it in scopeDescription, before the downstream attribute lookup.
        System.assert(res[0].scopeDescription.contains('GEO #2 - CALIFORNIA'), res[0].scopeDescription);
        System.assert(res[0].scopeDescription.contains('LOS ANGELES'), res[0].scopeDescription);
    }

    @isTest
    static void testScopedGroupWithNoBundlesOfProduct() {
        TestData td = makeGroupedQuote();
        Test.setMock(HttpCalloutMock.class, new SuccessMock());
        BulkUpdateBundleAttribute.Request req = new BulkUpdateBundleAttribute.Request();
        req.quoteId = td.quoteId;
        req.bundleProductId = td.bundleProductId;
        req.attributeName = 'Operating System';
        req.desiredValue = 'Redhat Enterprise Linux';
        req.groupNames = 'San Francisco';            // exists, but no bundle of this product
        List<BulkUpdateBundleAttribute.Result> res =
            BulkUpdateBundleAttribute.execute(new List<BulkUpdateBundleAttribute.Request>{ req });
        System.assertEquals(false, res[0].isSuccess);
        System.assert(res[0].errorMessage.contains('requested group'), res[0].errorMessage);
    }

    private class TestData {
        Id quoteId;
        Id bundleProductId;
    }

    private static TestData makeGroupedQuote() {
        Product2 bundle = new Product2(Name = 'QuantumBit Complete Solution', IsActive = true);
        insert bundle;
        Id stdPb = Test.getStandardPricebookId();
        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = stdPb, Product2Id = bundle.Id, UnitPrice = 100, IsActive = true);
        insert pbe;

        Quote q = new Quote(Name = 'Scoped Attr Test', Pricebook2Id = stdPb);
        insert q;

        QuoteLineGroup ny = new QuoteLineGroup(Name = 'GEO #1 - NEW YORK', QuoteId = q.Id);
        QuoteLineGroup ca = new QuoteLineGroup(Name = 'GEO #2 - CALIFORNIA', QuoteId = q.Id);
        insert new List<QuoteLineGroup>{ ny, ca };
        QuoteLineGroup la = new QuoteLineGroup(Name = 'LOS ANGELES', QuoteId = q.Id, ParentQuoteLineGroupId = ca.Id);
        QuoteLineGroup sf = new QuoteLineGroup(Name = 'SAN FRANCISCO', QuoteId = q.Id, ParentQuoteLineGroupId = ca.Id);
        insert new List<QuoteLineGroup>{ la, sf };

        List<QuoteLineItem> qlis = new List<QuoteLineItem>{
            new QuoteLineItem(QuoteId = q.Id, Product2Id = bundle.Id, PricebookEntryId = pbe.Id,
                Quantity = 1, UnitPrice = 100, QuoteLineGroupId = ny.Id),
            new QuoteLineItem(QuoteId = q.Id, Product2Id = bundle.Id, PricebookEntryId = pbe.Id,
                Quantity = 1, UnitPrice = 100, QuoteLineGroupId = la.Id)
        };
        insert qlis;

        TestData td = new TestData();
        td.quoteId = q.Id;
        td.bundleProductId = bundle.Id;
        return td;
    }
}
