from fastapi import APIRouter

from app.core.response import success

router = APIRouter()


@router.get("/health")
def module_health() -> dict:
    return success({"module": "api", "status": "ok"})
