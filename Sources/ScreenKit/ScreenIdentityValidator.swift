#if canImport(UIKit)
/// Finds duplicate identities before a diffable snapshot is constructed.
///
/// Diagnostics report positions rather than identifier values so application
/// data used as an identifier is not written to logs.
internal enum ScreenIdentityValidator {
    internal struct ItemLocation: Equatable {
        let section: Int
        let item: Int
    }

    internal static func duplicateSectionMessage<ID: Hashable>(in ids: [ID]) -> String? {
        var firstPositionByID: [ID: Int] = [:]
        for (position, id) in ids.enumerated() {
            if let firstPosition = firstPositionByID[id] {
                return "Screen section IDs must be unique; duplicate at sections[\(firstPosition)] and sections[\(position)]."
            }
            firstPositionByID[id] = position
        }
        return nil
    }

    internal static func duplicateItemMessage<SectionID: Hashable & Sendable, Item, ItemID: Hashable>(
        in sections: [ScreenSection<SectionID, Item>],
        id: (Item) -> ItemID
    ) -> String? {
        var firstPositionByID: [ItemID: ItemLocation] = [:]
        for (sectionPosition, section) in sections.enumerated() {
            for (itemPosition, item) in section.items.enumerated() {
                let itemID = id(item)
                let location = ItemLocation(section: sectionPosition, item: itemPosition)
                if let firstLocation = firstPositionByID[itemID] {
                    return "Screen item IDs must be globally unique; duplicate at "
                        + "sections[\(firstLocation.section)].items[\(firstLocation.item)] and "
                        + "sections[\(location.section)].items[\(location.item)]."
                }
                firstPositionByID[itemID] = location
            }
        }
        return nil
    }
}
#endif
