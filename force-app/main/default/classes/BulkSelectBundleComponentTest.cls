@isTest
private class BulkSelectBundleComponentTest {

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

    private class RuleBlockedMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse resp = new HttpResponse();
            resp.setStatusCode(201);
            if (req.getEndpoint().contains('load-instance')) {
                resp.setBody('{"success":true,"contextId":"ctx_test"}');
            } else {
                resp.setBody('{"success":true,"errors":[],"configuratorMessages":{"b":[{"messageType":"warning","category":"bundlevalidation","message":"Select child products in the range 1-1 and try again."}]}}');
            }
            return resp;
        }
    }


    @isTest
    static void testInvalidOperation() {
        BulkSelectBundleComponent.Request req = new BulkSelectBundleComponent.Request();
        req.operation = 'BOGUS';
        req.quoteId = '0Q0000000000001AAA';
        req.bundleProductId = '01t000000000001AAA';
        List<BulkSelectBundleComponent.Result> res =
            BulkSelectBundleComponent.execute(new List<BulkSelectBundleComponent.Request>{ req });
        System.assertEquals(false, res[0].isSuccess);
        System.assert(res[0].errorMessage.contains('SELECT, DESELECT, or SWAP'), res[0].errorMessage);
    }

    @isTest
    static void testSelectMissingPrc() {
        BulkSelectBundleComponent.Request req = new BulkSelectBundleComponent.Request();
        req.operation = 'SELECT';
        req.quoteId = '0Q0000000000001AAA';
        req.bundleProductId = '01t000000000001AAA';
        // no productRelatedComponentId
        List<BulkSelectBundleComponent.Result> res =
            BulkSelectBundleComponent.execute(new List<BulkSelectBundleComponent.Request>{ req });
        System.assertEquals(false, res[0].isSuccess);
        System.assert(res[0].errorMessage.contains('productRelatedComponentId'));
    }

    @isTest
    static void testDeselectMissingChild() {
        BulkSelectBundleComponent.Request req = new BulkSelectBundleComponent.Request();
        req.operation = 'DESELECT';
        req.quoteId = '0Q0000000000001AAA';
        req.bundleProductId = '01t000000000001AAA';
        // no childProductId
        List<BulkSelectBundleComponent.Result> res =
            BulkSelectBundleComponent.execute(new List<BulkSelectBundleComponent.Request>{ req });
        System.assertEquals(false, res[0].isSuccess);
        System.assert(res[0].errorMessage.contains('childProductId'));
    }

    @isTest
    static void testNoInstancesFound() {
        // Valid inputs but no matching bundle instances on the (non-existent) quote.
        Test.setMock(HttpCalloutMock.class, new SuccessMock());
        BulkSelectBundleComponent.Request req = new BulkSelectBundleComponent.Request();
        req.operation = 'SELECT';
        req.quoteId = '0Q0000000000123AAA';
        req.bundleProductId = '01t000000000123AAA';
        req.productRelatedComponentId = '0dS000000000123AAA';
        List<BulkSelectBundleComponent.Result> res =
            BulkSelectBundleComponent.execute(new List<BulkSelectBundleComponent.Request>{ req });
        System.assertEquals(false, res[0].isSuccess);
        System.assertEquals(0, res[0].totalBundles);
        System.assert(res[0].errorMessage.contains('No instances'));
    }

    @isTest
    static void testConfiguratorClientHelpers() {
        // Exercise the shared util's pure builders (no callout).
        ProductRelatedComponent prc = new ProductRelatedComponent();
        // ChildProductId left null is fine for node-shape coverage.
        PricebookEntry pbe = new PricebookEntry();
        List<Object> nodes = ConfiguratorClient.buildSelectNodes(
            '0Q0000000000001AAA', '0QL000000000001AAA', prc, pbe, '1_999');
        System.assertEquals(2, nodes.size(), 'Expected QLI + relationship nodes');
        Map<String, Object> relNode = (Map<String, Object>) nodes[1];
        Map<String, Object> relObj = (Map<String, Object>) relNode.get('addedObject');
        System.assertEquals('QuoteLineRelationship', relObj.get('businessObjectType'),
            'Relationship node must use QuoteLineRelationship');
        Map<String, Object> del = ConfiguratorClient.buildDeleteNode('0Q0000000000001AAA', '0QL000000000002AAA');
        System.assert(del.containsKey('path'));
    }

    @isTest
    static void testExtractBlockingMessage() {
        Map<String, Object> blocked = (Map<String, Object>) JSON.deserializeUntyped(
            '{"configuratorMessages":{"b":[{"messageType":"warning","category":"bundlevalidation","message":"range 1-1"}]}}');
        System.assertNotEquals(null, ConfiguratorClient.extractBlockingMessage(blocked));
        Map<String, Object> clean = (Map<String, Object>) JSON.deserializeUntyped(
            '{"configuratorMessages":{}}');
        System.assertEquals(null, ConfiguratorClient.extractBlockingMessage(clean));
    }

    // ── Group-scoping tests ──────────────────────────────────────────────
    // Builds a quote: NEW YORK (root, 2 bundles), CALIFORNIA (root, 0 direct) with
    // subgroup LOS ANGELES (1 bundle). Bundle product = `p`.
    @isTest
    static void testScopedUnmatchedGroupFailsWithoutCallout() {
        TestData td = makeGroupedQuote();
        // No mock set: if the class makes ANY callout it throws, proving fail-fast is callout-free.
        BulkSelectBundleComponent.Request req = new BulkSelectBundleComponent.Request();
        req.operation = 'SELECT';
        req.quoteId = td.quoteId;
        req.bundleProductId = td.bundleProductId;
        req.productRelatedComponentId = '0dS000000000123AAA';
        req.groupNames = 'Florida';
        List<BulkSelectBundleComponent.Result> res =
            BulkSelectBundleComponent.execute(new List<BulkSelectBundleComponent.Request>{ req });
        System.assertEquals(false, res[0].isSuccess);
        System.assert(res[0].errorMessage.contains('not found'), res[0].errorMessage);
        System.assert(res[0].errorMessage.contains('GEO #1 - NEW YORK'),
            'should list available groups: ' + res[0].errorMessage);
    }

    @isTest
    static void testScopedToNewYorkOnlyCountsScoped() {
        TestData td = makeGroupedQuote();
        Test.setMock(HttpCalloutMock.class, new SuccessMock());
        BulkSelectBundleComponent.Request req = new BulkSelectBundleComponent.Request();
        req.operation = 'DESELECT';                 // DESELECT avoids needing a PRC/pricebook
        req.quoteId = td.quoteId;
        req.bundleProductId = td.bundleProductId;
        req.childProductId = td.childProductId;     // not present as a child -> all SKIPPED_ALREADY
        req.groupNames = 'New York';
        List<BulkSelectBundleComponent.Result> res =
            BulkSelectBundleComponent.execute(new List<BulkSelectBundleComponent.Request>{ req });
        // Scoped to NY's 2 bundles (not the 3 on the quote).
        System.assertEquals(2, res[0].totalBundles, 'totalBundles must be the SCOPED count');
        System.assertEquals('GEO #1 - NEW YORK', res[0].scopeDescription);
    }

    @isTest
    static void testScopedToCaliforniaIncludesSubgroup() {
        TestData td = makeGroupedQuote();
        Test.setMock(HttpCalloutMock.class, new SuccessMock());
        BulkSelectBundleComponent.Request req = new BulkSelectBundleComponent.Request();
        req.operation = 'DESELECT';
        req.quoteId = td.quoteId;
        req.bundleProductId = td.bundleProductId;
        req.childProductId = td.childProductId;
        req.groupNames = 'California';
        List<BulkSelectBundleComponent.Result> res =
            BulkSelectBundleComponent.execute(new List<BulkSelectBundleComponent.Request>{ req });
        // California has 0 direct bundles but 1 in its LA subgroup -> 1 scoped.
        System.assertEquals(1, res[0].totalBundles, 'must include subgroup bundles');
        System.assert(res[0].scopeDescription.contains('LOS ANGELES'),
            'scope desc should note the subgroup: ' + res[0].scopeDescription);
    }

    @isTest
    static void testScopedGroupWithNoBundlesOfProduct() {
        TestData td = makeGroupedQuote();
        Test.setMock(HttpCalloutMock.class, new SuccessMock());
        // SAN FRANCISCO exists but has no bundle of this product.
        BulkSelectBundleComponent.Request req = new BulkSelectBundleComponent.Request();
        req.operation = 'DESELECT';
        req.quoteId = td.quoteId;
        req.bundleProductId = td.bundleProductId;
        req.childProductId = td.childProductId;
        req.groupNames = 'San Francisco';
        List<BulkSelectBundleComponent.Result> res =
            BulkSelectBundleComponent.execute(new List<BulkSelectBundleComponent.Request>{ req });
        System.assertEquals(false, res[0].isSuccess);
        System.assert(res[0].errorMessage.contains('requested group'), res[0].errorMessage);
    }

    @isTest
    static void testUnscopedBackwardCompatible() {
        TestData td = makeGroupedQuote();
        Test.setMock(HttpCalloutMock.class, new SuccessMock());
        BulkSelectBundleComponent.Request req = new BulkSelectBundleComponent.Request();
        req.operation = 'DESELECT';
        req.quoteId = td.quoteId;
        req.bundleProductId = td.bundleProductId;
        req.childProductId = td.childProductId;
        // no groupNames -> whole quote (all 3 bundles)
        List<BulkSelectBundleComponent.Result> res =
            BulkSelectBundleComponent.execute(new List<BulkSelectBundleComponent.Request>{ req });
        System.assertEquals(3, res[0].totalBundles, 'unscoped must see all instances');
        System.assertEquals('entire quote', res[0].scopeDescription);
    }

    // ── SWAP tests ───────────────────────────────────────────────────────

    @isTest
    static void testSwapMissingArgsFails() {
        BulkSelectBundleComponent.Request req = new BulkSelectBundleComponent.Request();
        req.operation = 'SWAP';
        req.quoteId = '0Q0000000000001AAA';
        req.bundleProductId = '01t000000000001AAA';
        req.productRelatedComponentId = '0dS000000000001AAA';
        // missing childProductId (the option to remove)
        List<BulkSelectBundleComponent.Result> res =
            BulkSelectBundleComponent.execute(new List<BulkSelectBundleComponent.Request>{ req });
        System.assertEquals(false, res[0].isSuccess);
        System.assert(res[0].errorMessage.contains('SWAP requires'), res[0].errorMessage);
    }

    // NOTE on SWAP coverage: a full unit test of the present-child swap (delete old + add new
    // in one session, ignoring the transient mid-swap "range 1-1" block) cannot be set up via
    // DML in this org. It requires a nested child line item (ParentQuoteLineItemId is
    // configurator-managed and not DML-writeable) and a configurable bundle product with a
    // ProductRelatedComponent (the parent must be a configurable bundle type). Those are
    // configurator-provisioned, not test-insertable. The SWAP execution path is therefore
    // verified LIVE end-to-end on the real NY bundles (delete-then-add, transient block ignored,
    // final state clean, then reverted), which is the authoritative test. The deterministic
    // unit coverage here is the argument validation (testSwapMissingArgsFails).

    private class TestData {
        Id quoteId;
        Id bundleProductId;
        Id childProductId;
    }

    private static TestData makeGroupedQuote() {
        Product2 bundle = new Product2(Name = 'QuantumBit Complete Solution', IsActive = true);
        Product2 child = new Product2(Name = 'QuantumBit Fundamentals Training', IsActive = true);
        insert new List<Product2>{ bundle, child };

        Id stdPb = Test.getStandardPricebookId();
        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = stdPb, Product2Id = bundle.Id, UnitPrice = 100, IsActive = true);
        insert pbe;

        Quote q = new Quote(Name = 'Scoped Bulk Test', Pricebook2Id = stdPb);
        insert q;

        QuoteLineGroup ny = new QuoteLineGroup(Name = 'GEO #1 - NEW YORK', QuoteId = q.Id);
        QuoteLineGroup ca = new QuoteLineGroup(Name = 'GEO #2 - CALIFORNIA', QuoteId = q.Id);
        insert new List<QuoteLineGroup>{ ny, ca };
        QuoteLineGroup la = new QuoteLineGroup(Name = 'LOS ANGELES', QuoteId = q.Id, ParentQuoteLineGroupId = ca.Id);
        QuoteLineGroup sf = new QuoteLineGroup(Name = 'SAN FRANCISCO', QuoteId = q.Id, ParentQuoteLineGroupId = ca.Id);
        insert new List<QuoteLineGroup>{ la, sf };

        List<QuoteLineItem> qlis = new List<QuoteLineItem>();
        for (Integer i = 0; i < 2; i++) {
            qlis.add(new QuoteLineItem(QuoteId = q.Id, Product2Id = bundle.Id,
                PricebookEntryId = pbe.Id, Quantity = 1, UnitPrice = 100, QuoteLineGroupId = ny.Id));
        }
        qlis.add(new QuoteLineItem(QuoteId = q.Id, Product2Id = bundle.Id,
            PricebookEntryId = pbe.Id, Quantity = 1, UnitPrice = 100, QuoteLineGroupId = la.Id));
        insert qlis;

        TestData td = new TestData();
        td.quoteId = q.Id;
        td.bundleProductId = bundle.Id;
        td.childProductId = child.Id;
        return td;
    }
}
