import Foundation

/// Starter chores so the app is useful on day one. Kira and Brandon can
/// edit or delete any of them.
public enum SeedChores {
    public static let all: [Chore] = [
        Chore(name: "Kitchen counters", room: "Kitchen", minutes: 10, steps: [
            "Put away anything that doesn't live on the counter.",
            "Move what's left to one side.",
            "Spray with cleaner and wipe, including behind the faucet.",
            "Do the other side, then put things back neatly.",
        ]),
        Chore(name: "Load the dishwasher", room: "Kitchen", minutes: 10, steps: [
            "Scrape food into the trash.",
            "Plates and bowls on the bottom, facing the middle.",
            "Cups and glasses upside down on the top rack.",
            "Forks and spoons handle down, knives handle up.",
            "Hand-wash pans that don't fit. Start it if it's full.",
        ]),
        Chore(name: "Empty the dishwasher", room: "Kitchen", minutes: 8, steps: [
            "Check the dishes are clean and dry.",
            "Bottom rack first so top-rack drips don't land on it.",
            "Put everything where it lives. Ask if you're not sure.",
        ]),
        Chore(name: "Wipe the stove and microwave", room: "Kitchen", minutes: 10, steps: [
            "Make sure the stove is off and cool.",
            "Wipe crumbs off the stovetop, then spray and wipe.",
            "Microwave: wipe inside, the door and the handle.",
        ]),
        Chore(name: "Take out the trash", room: "Kitchen", minutes: 5, steps: [
            "Tie the bag and take it to the outside bin.",
            "Check the bathroom and bedroom trash cans too.",
            "Put a new bag in every can you emptied.",
        ]),
        Chore(name: "Sweep the kitchen floor", room: "Kitchen", minutes: 10, steps: [
            "Pull out the chairs.",
            "Sweep from the edges toward the middle.",
            "Get under the table and the edge of the cabinets.",
            "Dustpan into the trash. Put the chairs back.",
        ]),
        Chore(name: "Clean the bathroom sink and mirror", room: "Bathroom", minutes: 10, steps: [
            "Clear the counter.",
            "Spray the sink and faucet, scrub, rinse.",
            "Wipe the counter dry.",
            "Glass cleaner on the mirror, wipe top to bottom.",
        ]),
        Chore(name: "Clean the toilet", room: "Bathroom", minutes: 10, steps: [
            "Put toilet cleaner under the rim and let it sit.",
            "Spray and wipe the top, seat (both sides) and base.",
            "Scrub the bowl with the brush and flush.",
        ]),
        Chore(name: "Bathroom towels and floor", room: "Bathroom", minutes: 8, steps: [
            "Hang towels straight or put dirty ones in the laundry.",
            "Shake out the bath mat.",
            "Pick up anything on the floor and sweep or wipe it.",
        ]),
        Chore(name: "Pick up the living room", room: "Living room", minutes: 10, steps: [
            "Take anything that doesn't belong there back to its room.",
            "Dishes go to the kitchen.",
            "Fold the blankets and straighten the pillows.",
            "Stack remotes and magazines neatly.",
        ]),
        Chore(name: "Dust the living room", room: "Living room", minutes: 10, steps: [
            "Dry cloth or duster, top to bottom.",
            "TV stand, shelves, side tables, windowsills.",
            "Lift things up instead of dusting around them.",
        ]),
        Chore(name: "Vacuum the living room", room: "Living room", minutes: 15, steps: [
            "Pick up anything on the floor first.",
            "Vacuum in rows across the room.",
            "Get under the couch edge and along the walls.",
            "Put the vacuum away and wrap the cord.",
        ]),
        Chore(name: "Wipe the dining table", room: "Dining room", minutes: 5, steps: [
            "Clear everything off.",
            "Wipe with a damp cloth, then dry it.",
            "Push the chairs in.",
        ]),
        Chore(name: "Start a load of laundry", room: "Laundry", minutes: 5, steps: [
            "Grab the fullest hamper.",
            "Check pockets.",
            "Add detergent, pick the normal cycle, start it.",
        ]),
        Chore(name: "Fold and put away laundry", room: "Laundry", minutes: 15, steps: [
            "Empty the dryer onto a bed or couch.",
            "Fold shirts, pants and towels into piles by person.",
            "Pair the socks.",
            "Take each pile to its room and put it away.",
        ]),
        Chore(name: "Make the beds", room: "Bedrooms", minutes: 8, steps: [
            "Pull the sheet and blanket straight up to the pillows.",
            "Fluff the pillows and line them up at the top.",
            "Smooth it out so nothing hangs lower on one side.",
        ]),
        Chore(name: "Pick up your bedroom", room: "Bedrooms", minutes: 15, steps: [
            "Dirty clothes in the hamper.",
            "Dishes and cups to the kitchen.",
            "Trash in the trash.",
            "Clear the floor and the top of the dresser.",
        ]),
        Chore(name: "Clean the entryway", room: "Entry", minutes: 8, steps: [
            "Line up the shoes.",
            "Hang coats and bags.",
            "Shake out the rug and sweep.",
        ]),
        Chore(name: "Wipe light switches and door handles", room: "Whole house", minutes: 10, steps: [
            "Disinfecting wipe or sprayed cloth.",
            "Every light switch and door handle you pass.",
            "Don't forget the fridge and microwave handles.",
        ]),
        Chore(name: "Water the plants", room: "Whole house", minutes: 5, steps: [
            "Feel the soil. Water only if it's dry an inch down.",
            "Water slowly until it just starts to drain.",
            "Wipe up any spills.",
        ]),
    ]
}
