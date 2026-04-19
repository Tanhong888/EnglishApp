from typing import Any


def paginate_list(items: list[Any], page: int, size: int) -> dict[str, Any]:
    start = (page - 1) * size
    end = start + size
    total = len(items)
    sliced = items[start:end]
    has_next = end < total

    return {
        "items": sliced,
        "page": page,
        "size": size,
        "total": total,
        "has_next": has_next,
    }
