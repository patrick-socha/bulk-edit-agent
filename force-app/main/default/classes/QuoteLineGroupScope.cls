/**
 * Resolves casual region/group names (e.g. "California, New York") to the exact set of
 * QuoteLineGroup IDs a bulk operation should be limited to — INCLUDING all transitive
 * descendant subgroups of each matched group.
 *
 * Why descendants matter: a group like "GEO #2 - CALIFORNIA" often has NO line items
 * directly under it — its bundles live in subgroups ("LOS ANGELES", "SAN FRANCISCO").
 * Scoping to "California" must therefore pull in those subgroups, or the rep gets a
 * confusing "0 bundles" on a region they can plainly see has bundles.
 *
 * Used by BulkSelectBundleComponent and BulkUpdateBundleAttribute. This class only
 * resolves NAMES -> GROUP IDS; it never touches the configurator session. The bulk
 * classes keep loading the WHOLE quote (load-instance) and only filter which instances
 * they MUTATE by QuoteLineItem.QuoteLineGroupId — so out-of-scope groups are always
 * preserved on save.
 */
public with sharing class QuoteLineGroupScope {

    // Defensive guard against cyclic ParentQuoteLineGroupId data so BFS always terminates.
    private static final Integer MAX_DEPTH = 20;

    public class ScopeResult {
        /** Matched groups + ALL their transitive descendant subgroups. Empty when not scoping. */
        public Set<Id> groupIds = new Set<Id>();
        /** Canonical Names of the groups that directly matched a requested token (sorted). */
        public List<String> matchedGroupNames = new List<String>();
        /** Requested tokens that matched no group on the quote. */
        public List<String> unmatchedTokens = new List<String>();
        /** All group Names on the quote (sorted) — for grounding/error messages. */
        public List<String> availableGroupNames = new List<String>();
        /** token -> how many groups it matched (>1 flags an over-broad token). */
        public Map<String, Integer> tokenMatchCounts = new Map<String, Integer>();
        /** Human-readable scope summary, e.g. "New York, California (incl. Los Angeles, San Francisco)". */
        public String scopeDescription = 'entire quote';
        /** False when no names were requested — caller treats as whole-quote (today's behavior). */
        public Boolean scopingRequested = false;
    }

    /** Convenience entry point: split a comma-separated string then resolve. */
    public static ScopeResult resolveFromCsv(Id quoteId, String csv) {
        return resolve(quoteId, splitNames(csv));
    }

    /**
     * Resolve requested group names to a ScopeResult. requestedNames may be null/empty
     * (=> scopingRequested false). Names are matched tolerantly (exact-normalized first,
     * then substring) and each match is expanded to include its descendant subgroups.
     */
    public static ScopeResult resolve(Id quoteId, List<String> requestedNames) {
        ScopeResult res = new ScopeResult();

        // No names requested -> whole-quote (backward compatible). Skip the query entirely.
        List<String> tokens = new List<String>();
        if (requestedNames != null) {
            for (String n : requestedNames) {
                if (String.isNotBlank(n)) { tokens.add(n.trim()); }
            }
        }
        if (tokens.isEmpty()) {
            return res; // scopingRequested stays false
        }
        res.scopingRequested = true;

        // The ONE new SOQL. Whole-quote, bulk-safe, user-mode.
        List<QuoteLineGroup> groups = [
            SELECT Id, Name, ParentQuoteLineGroupId
            FROM QuoteLineGroup
            WHERE QuoteId = :quoteId
            WITH USER_MODE
        ];

        Map<Id, QuoteLineGroup> byId = new Map<Id, QuoteLineGroup>();
        Map<Id, List<Id>> childrenByParent = new Map<Id, List<Id>>();
        List<String> available = new List<String>();
        for (QuoteLineGroup g : groups) {
            byId.put(g.Id, g);
            available.add(g.Name);
            if (g.ParentQuoteLineGroupId != null) {
                if (!childrenByParent.containsKey(g.ParentQuoteLineGroupId)) {
                    childrenByParent.put(g.ParentQuoteLineGroupId, new List<Id>());
                }
                childrenByParent.get(g.ParentQuoteLineGroupId).add(g.Id);
            }
        }
        available.sort();
        res.availableGroupNames = available;

        // Match each token to seed groups. Exact-normalized match wins; else substring.
        Set<Id> seeds = new Set<Id>();
        Set<String> matchedNames = new Set<String>();
        for (String token : tokens) {
            String nt = normalize(token);
            List<Id> exactHits = new List<Id>();
            List<Id> containsHits = new List<Id>();
            for (QuoteLineGroup g : groups) {
                String ng = normalize(g.Name);
                if (ng == nt) {
                    exactHits.add(g.Id);
                } else if (ng.contains(nt) || nt.contains(ng)) {
                    containsHits.add(g.Id);
                }
            }
            List<Id> hits = !exactHits.isEmpty() ? exactHits : containsHits;
            res.tokenMatchCounts.put(token, hits.size());
            if (hits.isEmpty()) {
                res.unmatchedTokens.add(token);
            } else {
                for (Id gid : hits) {
                    seeds.add(gid);
                    matchedNames.add(byId.get(gid).Name);
                }
            }
        }

        // Expand seeds to include all transitive descendant subgroups (BFS, cycle-safe).
        Set<Id> all = new Set<Id>(seeds);
        List<Id> frontier = new List<Id>(seeds);
        Integer depth = 0;
        while (!frontier.isEmpty() && depth < MAX_DEPTH) {
            List<Id> next = new List<Id>();
            for (Id pid : frontier) {
                List<Id> kids = childrenByParent.get(pid);
                if (kids == null) { continue; }
                for (Id kid : kids) {
                    if (!all.contains(kid)) {
                        all.add(kid);
                        next.add(kid);
                    }
                }
            }
            frontier = next;
            depth++;
        }
        res.groupIds = all;

        List<String> matchedSorted = new List<String>(matchedNames);
        matchedSorted.sort();
        res.matchedGroupNames = matchedSorted;
        res.scopeDescription = buildDescription(matchedSorted, seeds, all, byId);
        return res;
    }

    /** Split a comma-separated string into trimmed, non-blank tokens. */
    public static List<String> splitNames(String csv) {
        List<String> out = new List<String>();
        if (String.isBlank(csv)) { return out; }
        for (String part : csv.split(',')) {
            if (String.isNotBlank(part)) { out.add(part.trim()); }
        }
        return out;
    }

    /** Normalize a name for tolerant matching: collapse whitespace, trim, lowercase.
     *  Digits and '#' are preserved (group names look like "GEO #2 - CALIFORNIA"). */
    private static String normalize(String name) {
        if (name == null) { return ''; }
        return name.replaceAll('\\s+', ' ').trim().toLowerCase();
    }

    /** Build "New York, California (incl. Los Angeles, San Francisco)" style summary. */
    private static String buildDescription(List<String> matchedNames, Set<Id> seeds,
            Set<Id> all, Map<Id, QuoteLineGroup> byId) {
        if (matchedNames.isEmpty()) { return 'no matching groups'; }
        List<String> subNames = new List<String>();
        for (Id gid : all) {
            if (!seeds.contains(gid)) { subNames.add(byId.get(gid).Name); }
        }
        subNames.sort();
        String summary = String.join(matchedNames, ', ');
        if (!subNames.isEmpty()) {
            summary += ' (incl. ' + String.join(subNames, ', ') + ')';
        }
        return summary;
    }
}
