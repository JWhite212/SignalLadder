// Sources/NotificationCore/SoundEditHistory.swift
import Foundation

/// The recipes before this one, this one and the recipes after it, for undo and
/// redo (Ruling 2).
///
/// A recipe is a small value that holds no audio, so keeping every one costs
/// almost nothing, and undoing is putting one back. Every edit the window makes
/// goes through `commit`, so there is one place that decides what is a change:
/// an edit that is refused, or that leaves the recipe as it was, adds nothing
/// to the past and does not take the future away.
public struct SoundEditHistory: Equatable, Sendable {
    /// The recipe the window opened with: what it is to be compared with to
    /// say that something has been changed and not saved.
    public let opened: SoundRecipe
    /// The recipe as it is now.
    public private(set) var present: SoundRecipe
    /// The recipe the sound on disk was last made from: the one the window opened with, until a save. It is what
    /// closing the window is asked about, and is not the same as `opened`, which a save does not change.
    public private(set) var saved: SoundRecipe
    private var past: [SoundRecipe] = []
    private var future: [SoundRecipe] = []

    public init(_ recipe: SoundRecipe) {
        opened = recipe
        present = recipe
        saved = recipe
    }

    public var canUndo: Bool { !past.isEmpty }
    public var canRedo: Bool { !future.isEmpty }

    /// Whether the recipe is not the one the window opened with.
    public var isChanged: Bool { present != opened }

    /// Whether the sound as the window shows it is not the sound that was last saved, so that closing would lose
    /// something. An undo past a save is such a change, and redoing back to it is not.
    public var hasUnsavedEdits: Bool { present != saved }

    /// Says that `recipe`, which a save wrote, is what is saved. It is the recipe the save was given and not the
    /// present one, which an edit made while the save ran may have moved on from.
    public mutating func markSaved(_ recipe: SoundRecipe) {
        saved = recipe
    }

    /// Makes `edit` to the present recipe, which becomes the past, and forgets
    /// what could have been redone.
    ///
    /// - Returns: whether anything changed. False when the edit left the recipe
    ///   as it was, as a gain of 0 does: nothing is then added to the past.
    /// - Throws: `SoundEditRefusal`, with nothing changed.
    @discardableResult
    public mutating func commit(_ edit: SoundEdit) throws -> Bool {
        try commit(recipe: edit.applied(to: present))
    }

    /// Puts the whole source back, as an edit that can be undone: Reset to
    /// Original.
    ///
    /// - Returns: whether anything changed.
    @discardableResult
    public mutating func reset() -> Bool {
        commit(recipe: present.original)
    }

    /// Puts back the recipe before the last change.
    ///
    /// - Returns: whether there was one.
    @discardableResult
    public mutating func undo() -> Bool {
        guard let previous = past.popLast() else { return false }
        future.append(present)
        present = previous
        return true
    }

    /// Puts back the recipe that was undone.
    ///
    /// - Returns: whether there was one.
    @discardableResult
    public mutating func redo() -> Bool {
        guard let next = future.popLast() else { return false }
        past.append(present)
        present = next
        return true
    }

    private mutating func commit(recipe: SoundRecipe) -> Bool {
        guard recipe != present else { return false }
        past.append(present)
        present = recipe
        future.removeAll()
        return true
    }
}
