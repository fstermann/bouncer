/// Nested tags, as Obsidian writes them: `#work/bouncer` sits under `#work`, and filtering by
/// `work` finds both.
enum TagPath {
    static func parent(of tag: String) -> String? {
        tag.lastIndex(of: "/").map { String(tag[..<$0]) }
    }

    /// The last part, as a chip shows it beside its parent's.
    static func leaf(of tag: String) -> String {
        tag.lastIndex(of: "/").map { String(tag[tag.index(after: $0)...]) } ?? tag
    }

    /// `tag` and the tags above it, outermost first.
    static func lineage(of tag: String) -> [String] {
        (parent(of: tag).map(lineage) ?? []) + [tag]
    }

    /// Whether `tag` is `filter` or sits anywhere under it.
    static func matches(_ tag: String, _ filter: String) -> Bool {
        tag == filter || tag.hasPrefix(filter + "/")
    }

    /// `tags` as a tree, each after the tag above it, and the tags beside each other in `order`;
    /// those not in it follow, as they were. `tags` holds the tags above each of its tags.
    static func sorted(_ tags: [String], by order: [String]) -> [String] {
        let rank = { (tag: String) in [order.firstIndex(of: tag) ?? order.count, tags.firstIndex(of: tag) ?? 0] }
        let key = { (tag: String) in lineage(of: tag).flatMap(rank) }
        return tags.sorted { key($0).lexicographicallyPrecedes(key($1)) }
    }

    /// `order` with `tag` moved to where `target`, beside it under the same tag, stands among `tags`.
    /// Tags in `order` but not in `tags`, such as those only hidden todos carry, keep their place.
    static func moving(_ tag: String, onto target: String, in tags: [String], order: [String]) -> [String] {
        guard tag != target, parent(of: tag) == parent(of: target) else { return order }
        var full = order + sorted(tags, by: order).filter { !order.contains($0) }
        guard let from = full.firstIndex(of: tag), let to = full.firstIndex(of: target) else { return order }
        full.remove(at: from)
        let at = full.firstIndex(of: target) ?? to
        full.insert(tag, at: from < to ? at + 1 : at)
        return full
    }
}
