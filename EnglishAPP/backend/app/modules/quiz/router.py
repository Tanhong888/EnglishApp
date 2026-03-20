from fastapi import APIRouter
from pydantic import BaseModel

from app.core.response import success

router = APIRouter()


class QuizSubmitRequest(BaseModel):
    article_id: int
    answers: list[dict]


@router.get("/articles/{article_id}/quiz")
def get_article_quiz(article_id: int) -> dict:
    return success(
        {
            "article_id": article_id,
            "questions": [
                {
                    "question_id": 1,
                    "stem": "What is the main idea of the article?",
                    "options": ["A", "B", "C", "D"],
                }
            ],
        }
    )


@router.post("/quiz/submit")
def submit_quiz(payload: QuizSubmitRequest) -> dict:
    return success({"attempt_id": 7001, "article_id": payload.article_id, "accuracy": 0.66})


@router.get("/quiz/attempts/{attempt_id}")
def get_attempt(attempt_id: int) -> dict:
    return success(
        {
            "attempt_id": attempt_id,
            "correct_count": 2,
            "total_count": 3,
            "accuracy": 0.66,
            "wrong_items": [1],
        }
    )
