def original(lower, lists, listTriggers):
    for trigger in listTriggers:
        if lower.endswith(trigger):
            return lists[0] if lists else None

        for lst in lists:
            listLower = lst.lower()
            for t in listTriggers:
                if lower.endswith(t):
                    break

                parts = lower.split(t)
                possibleSuffix = parts[-1] if parts else ""

                if possibleSuffix and listLower.startswith(possibleSuffix) and possibleSuffix != listLower:
                    return lst[len(possibleSuffix):]
    return None

def optimized(lower, lists, listTriggers):
    for trigger in listTriggers:
        if lower.endswith(trigger):
            return lists[0] if lists else None

    # Precompute possible suffixes outside the list loop
    # We use a similar break logic: if lower.endswith(t), we stop processing further triggers for this list in the original.
    # Wait, in the original, if lower.endswith(t), it breaks the `t` loop, so it doesn't check subsequent triggers for that list.
    validSuffixes = []
    for t in listTriggers:
        if lower.endswith(t):
            break
        parts = lower.split(t)
        possibleSuffix = parts[-1] if parts else ""
        if possibleSuffix:
            validSuffixes.append((possibleSuffix, len(possibleSuffix)))

    for lst in lists:
        listLower = lst.lower()
        for possibleSuffix, count in validSuffixes:
            if listLower.startswith(possibleSuffix) and possibleSuffix != listLower:
                return lst[count:]
    return None

lists = ["Walmart", "Target", "Home Depot"]
listTriggers = ["in ", "to "]

tests = [
    "buy milk in wal",
    "go to tar",
    "go to ",
    "buy milk in ",
    "buy milk in wal to hom",
    "buy milk to hom in wal",
    "nothing here",
    "in "
]

for t in tests:
    o = original(t, lists, listTriggers)
    opt = optimized(t, lists, listTriggers)
    print(f"'{t}': original='{o}', optimized='{opt}'")
    if o != opt:
        print("MISMATCH!")
