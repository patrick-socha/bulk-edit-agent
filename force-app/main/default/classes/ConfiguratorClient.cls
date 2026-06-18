/**
 * Shared, stateless helpers for talking to the Product Configurator REST API and building
 * the node payloads used to select bundle components. Used by SelectBundleComponent (single)
 * and BulkSelectBundleComponent (all instances) so the payload contract lives in ONE place.
 *
 * Key contract details that must not drift:
 *  - The relationship node's businessObjectType MUST be 'QuoteLineRelationship'
 *    (NOT 'QuoteLineItemRelationship') or the child is created but not nested under the bundle.
 *  - The QuoteLineItem node MUST include UnitPrice or the configurator returns
 *    'productDetails is null'.
 *  - childRef / relRef MUST be unique per node within a session — callers pass a distinct
 *    refSuffix per (bundle instance, component) so adding the same component to multiple
 *    bundles in one session does not collide.
 */
public with sharing class ConfiguratorClient {

    private static final String BASE =
        '/services/data/v67.0/connect/cpq/configurator/actions/';

    public class ConfiguratorException extends Exception {}

    // ── Session lifecycle ────────────────────────────────────────────────

    /** Load a configurator session for a quote; returns the contextId or null on failure. */
    public static String loadSession(String quoteId) {
        Map<String, Object> body = new Map<String, Object>{ 'transactionId' => quoteId };
        HttpResponse resp = callConfigurator('load-instance', body);
        if (resp.getStatusCode() >= 200 && resp.getStatusCode() < 300) {
            Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(resp.getBody());
            return (String) parsed.get('contextId');
        }
        return null;
    }

    /** Commit the session back to the quote. */
    public static HttpResponse saveSession(String ctx) {
        return callConfigurator('save-instance', new Map<String, Object>{ 'contextId' => ctx });
    }

    /** Generic POST to a configurator action via the Named Credential. */
    public static HttpResponse callConfigurator(String action, Map<String, Object> body) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:Configurator_API' + BASE + action);
        req.setHeader('Content-Type', 'application/json');
        req.setMethod('POST');
        req.setBody(JSON.serialize(body));
        return new Http().send(req);
    }

    // ── Response inspection ──────────────────────────────────────────────

    /**
     * Returns a human-readable message if a bundle-validation rule blocks the change
     * (error/warning or category 'bundlevalidation'), else null. Walks configuratorMessages.
     */
    public static String extractBlockingMessage(Map<String, Object> parsed) {
        Object msgsObj = parsed.get('configuratorMessages');
        if (!(msgsObj instanceof Map<String, Object>)) { return null; }
        Map<String, Object> msgs = (Map<String, Object>) msgsObj;
        for (String key : msgs.keySet()) {
            Object listObj = msgs.get(key);
            if (!(listObj instanceof List<Object>)) { continue; }
            for (Object mObj : (List<Object>) listObj) {
                if (!(mObj instanceof Map<String, Object>)) { continue; }
                Map<String, Object> m = (Map<String, Object>) mObj;
                String type = (String) m.get('messageType');
                String category = (String) m.get('category');
                if (type == 'error' || type == 'warning'
                        || (category != null && category.equalsIgnoreCase('bundlevalidation'))) {
                    return (String) m.get('message');
                }
            }
        }
        return null;
    }

    // ── Pricing resolution ───────────────────────────────────────────────

    /**
     * Resolve an active PricebookEntry for a child product in the given pricebook.
     * Throws ConfiguratorException if none found.
     */
    public static PricebookEntry resolvePricebookEntry(Id childProductId, Id pricebookId) {
        List<PricebookEntry> pbes = [
            SELECT Id, UnitPrice, Product2Id, ProductSellingModelId
            FROM PricebookEntry
            WHERE Product2Id = :childProductId AND Pricebook2Id = :pricebookId AND IsActive = true
            WITH USER_MODE
            LIMIT 1
        ];
        if (pbes.isEmpty()) {
            throw new ConfiguratorException(
                'No active price found for the selected component in the quote price book.');
        }
        return pbes[0];
    }

    // ── Node construction ────────────────────────────────────────────────

    /**
     * Build the two add-nodes objects (QuoteLineItem + QuoteLineRelationship) that select one
     * predefined component (childProductId, via prc) under one bundle instance.
     * refSuffix MUST be unique per node within the session (e.g. "<instanceIndex>_<prcId>").
     */
    public static List<Object> buildSelectNodes(
        String quoteId,
        String bundleLineItemId,
        ProductRelatedComponent prc,
        PricebookEntry pbe,
        String refSuffix
    ) {
        String childRef = 'ref_child_' + refSuffix;
        String relRef = 'ref_rel_' + refSuffix;

        Map<String, Object> qliObj = new Map<String, Object>{
            'id' => childRef,
            'SalesTransactionItemSource' => childRef,
            'SalesTransactionItemParent' => quoteId,
            'PricebookEntry' => pbe.Id,
            'ProductSellingModel' => pbe.ProductSellingModelId,
            'UnitPrice' => pbe.UnitPrice,
            'Quantity' => 1,
            'Product' => prc.ChildProductId,
            'businessObjectType' => 'QuoteLineItem'
        };
        Map<String, Object> qliNode = new Map<String, Object>{
            'path' => new List<String>{ quoteId, childRef },
            'addedObject' => qliObj
        };
        // businessObjectType MUST be 'QuoteLineRelationship' — see class header.
        Map<String, Object> relObj = new Map<String, Object>{
            'id' => relRef,
            'MainItem' => bundleLineItemId,
            'AssociatedItem' => childRef,
            'ProductRelatedComponent' => prc.Id,
            'AssociatedItemPricing' => 'NotIncludedInBundlePrice',
            'AssociatedQuantScaleMethod' => 'Proportional',
            'businessObjectType' => 'QuoteLineRelationship'
        };
        Map<String, Object> relNode = new Map<String, Object>{
            'path' => new List<String>{ quoteId, childRef, relRef },
            'addedObject' => relObj
        };
        return new List<Object>{ qliNode, relNode };
    }

    /** Build a single delete node for deselecting a line item. */
    public static Map<String, Object> buildDeleteNode(String quoteId, String lineItemId) {
        return new Map<String, Object>{
            'path' => new List<String>{ quoteId, lineItemId }
        };
    }
}
