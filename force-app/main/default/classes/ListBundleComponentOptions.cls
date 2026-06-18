public with sharing class ListBundleComponentOptions {

    @InvocableMethod(
        label='List Bundle Component Options'
        description='For a bundle product on a quote, list its component groups and the predefined component options in each group, marking which are currently selected, which are required, and each group selection range (min/max). Use this to show a rep what they can select, swap, or deselect.'
    )
    public static List<Result> execute(List<Request> requests) {
        List<Result> results = new List<Result>();

        // Collect bundle product IDs + quote IDs
        Set<Id> bundleProductIds = new Set<Id>();
        Set<Id> quoteIds = new Set<Id>();
        for (Request req : requests) {
            if (String.isNotBlank(req.bundleProductId)) {
                try { bundleProductIds.add((Id) req.bundleProductId); } catch (Exception e) {}
            }
            if (String.isNotBlank(req.quoteId)) {
                try { quoteIds.add((Id) req.quoteId); } catch (Exception e) {}
            }
        }

        // Groups for these bundles
        Map<Id, List<ProductComponentGroup>> groupsByBundle = new Map<Id, List<ProductComponentGroup>>();
        if (!bundleProductIds.isEmpty()) {
            for (ProductComponentGroup g : [
                SELECT Id, Name, ParentProductId, MinBundleComponents, MaxBundleComponents
                FROM ProductComponentGroup
                WHERE ParentProductId IN :bundleProductIds
                WITH USER_MODE
            ]) {
                if (!groupsByBundle.containsKey(g.ParentProductId)) {
                    groupsByBundle.put(g.ParentProductId, new List<ProductComponentGroup>());
                }
                groupsByBundle.get(g.ParentProductId).add(g);
            }
        }

        // Options (ProductRelatedComponent) for these bundles
        Map<Id, List<ProductRelatedComponent>> prcByGroup = new Map<Id, List<ProductRelatedComponent>>();
        if (!bundleProductIds.isEmpty()) {
            for (ProductRelatedComponent prc : [
                SELECT Id, ChildProductId, ChildProduct.Name, ProductComponentGroupId,
                       IsComponentRequired, IsDefaultComponent, IsQuantityEditable,
                       MinQuantity, MaxQuantity
                FROM ProductRelatedComponent
                WHERE ParentProductId IN :bundleProductIds
                WITH USER_MODE
            ]) {
                if (prc.ProductComponentGroupId == null) { continue; }
                if (!prcByGroup.containsKey(prc.ProductComponentGroupId)) {
                    prcByGroup.put(prc.ProductComponentGroupId, new List<ProductRelatedComponent>());
                }
                prcByGroup.get(prc.ProductComponentGroupId).add(prc);
            }
        }

        // Currently-selected child products per quote (to mark isSelected)
        Map<Id, Map<Id, Id>> selectedByQuote = new Map<Id, Map<Id, Id>>(); // quoteId -> (childProductId -> lineItemId)
        if (!quoteIds.isEmpty()) {
            for (QuoteLineItem qli : [
                SELECT Id, Product2Id, QuoteId
                FROM QuoteLineItem
                WHERE QuoteId IN :quoteIds
                WITH USER_MODE
            ]) {
                if (!selectedByQuote.containsKey(qli.QuoteId)) {
                    selectedByQuote.put(qli.QuoteId, new Map<Id, Id>());
                }
                selectedByQuote.get(qli.QuoteId).put(qli.Product2Id, qli.Id);
            }
        }

        for (Request req : requests) {
            Result r = new Result();
            try {
                if (String.isBlank(req.bundleProductId) || String.isBlank(req.quoteId)) {
                    r.isSuccess = false;
                    r.errorMessage = 'Both quoteId and bundleProductId are required.';
                    results.add(r);
                    continue;
                }
                Map<Id, Id> selected = selectedByQuote.containsKey((Id) req.quoteId)
                    ? selectedByQuote.get((Id) req.quoteId) : new Map<Id, Id>();
                List<ProductComponentGroup> groups = groupsByBundle.get((Id) req.bundleProductId);
                List<Map<String, Object>> groupOut = new List<Map<String, Object>>();
                if (groups != null) {
                    for (ProductComponentGroup g : groups) {
                        List<Map<String, Object>> opts = new List<Map<String, Object>>();
                        List<ProductRelatedComponent> prcs = prcByGroup.get(g.Id);
                        if (prcs != null) {
                            for (ProductRelatedComponent prc : prcs) {
                                opts.add(new Map<String, Object>{
                                    'productRelatedComponentId' => prc.Id,
                                    'childProductId' => prc.ChildProductId,
                                    'productName' => prc.ChildProduct != null ? prc.ChildProduct.Name : null,
                                    'isRequired' => prc.IsComponentRequired,
                                    'isDefault' => prc.IsDefaultComponent,
                                    'isSelected' => selected.containsKey(prc.ChildProductId),
                                    'selectedLineItemId' => selected.get(prc.ChildProductId)
                                });
                            }
                        }
                        groupOut.add(new Map<String, Object>{
                            'groupId' => g.Id,
                            'groupName' => g.Name,
                            'minComponents' => g.MinBundleComponents,
                            'maxComponents' => g.MaxBundleComponents,
                            'options' => opts
                        });
                    }
                }
                r.isSuccess = true;
                r.groupCount = groupOut.size();
                r.optionsJson = JSON.serialize(groupOut);
            } catch (Exception e) {
                r.isSuccess = false;
                r.errorMessage = e.getMessage();
            }
            results.add(r);
        }

        return results;
    }

    public class Request {
        @InvocableVariable(
            label='Quote ID'
            description='The Quote being configured'
            required=true
        )
        public String quoteId;

        @InvocableVariable(
            label='Bundle Product ID'
            description='The Product2 ID of the bundle whose component options to list'
            required=true
        )
        public String bundleProductId;
    }

    public class Result {
        @InvocableVariable(
            label='Is Success'
            description='True if the options were retrieved'
        )
        public Boolean isSuccess;

        @InvocableVariable(
            label='Error Message'
            description='Error detail when isSuccess is false'
        )
        public String errorMessage;

        @InvocableVariable(
            label='Options JSON'
            description='JSON array of component groups; each has groupId, groupName, minComponents, maxComponents, and options[] with productRelatedComponentId, childProductId, productName, isRequired, isDefault, isSelected, selectedLineItemId'
        )
        public String optionsJson;

        @InvocableVariable(
            label='Group Count'
            description='Number of component groups on the bundle'
        )
        public Integer groupCount;
    }
}
