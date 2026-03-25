from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.rate_limit import SlidingWindowRateLimiter
from app.core.response import success
from app.db.models import Article, Quiz, QuizOption, QuizQuestion, UserQuizAnswer, UserQuizAttempt
from app.db.session import get_db

router = APIRouter()

QUIZ_SUBMIT_LIMIT_PER_MINUTE = 30
QUIZ_SUBMIT_WINDOW_SECONDS = 60
_quiz_submit_rate_limiter = SlidingWindowRateLimiter(
    limit_per_window=QUIZ_SUBMIT_LIMIT_PER_MINUTE,
    window_seconds=QUIZ_SUBMIT_WINDOW_SECONDS,
    error_detail='quiz_submit_rate_limited',
)


class QuizSubmitRequest(BaseModel):
    article_id: int
    answers: list[dict]


def _sync_quiz_submit_rate_limit_config() -> None:
    _quiz_submit_rate_limiter.limit_per_window = QUIZ_SUBMIT_LIMIT_PER_MINUTE
    _quiz_submit_rate_limiter.window_seconds = QUIZ_SUBMIT_WINDOW_SECONDS


def reset_quiz_submit_rate_limit_state_for_test() -> None:
    _sync_quiz_submit_rate_limit_config()
    _quiz_submit_rate_limiter.reset()


def _quiz_rate_limit_keys(request: Request) -> list[str]:
    client_host = request.client.host if request.client else 'unknown'
    return [f'ip:{client_host}']


def _get_quiz_or_404(article_id: int, db: Session) -> tuple[Article, Quiz]:
    article = db.get(Article, article_id)
    if article is None or not article.is_published:
        raise HTTPException(status_code=404, detail='article not found')
    quiz = db.scalar(select(Quiz).where(Quiz.article_id == article_id))
    if quiz is None:
        raise HTTPException(status_code=404, detail='quiz not found')
    return article, quiz


@router.get('/articles/{article_id}/quiz')
def get_article_quiz(article_id: int, db: Session = Depends(get_db)) -> dict:
    _, quiz = _get_quiz_or_404(article_id, db)
    questions = db.scalars(
        select(QuizQuestion).where(QuizQuestion.quiz_id == quiz.id).order_by(QuizQuestion.question_index.asc(), QuizQuestion.id.asc())
    ).all()

    serialized_questions: list[dict] = []
    for question in questions:
        options = db.scalars(
            select(QuizOption)
            .where(QuizOption.question_id == question.id)
            .order_by(QuizOption.option_index.asc(), QuizOption.id.asc())
        ).all()
        serialized_questions.append(
            {
                'question_id': question.id,
                'stem': question.stem,
                'options': [option.content for option in options],
            }
        )

    return success({'article_id': article_id, 'questions': serialized_questions})


@router.post('/quiz/submit')
def submit_quiz(payload: QuizSubmitRequest, request: Request, db: Session = Depends(get_db)) -> dict:
    _sync_quiz_submit_rate_limit_config()
    _quiz_submit_rate_limiter.enforce(_quiz_rate_limit_keys(request))

    _, quiz = _get_quiz_or_404(payload.article_id, db)
    questions = db.scalars(
        select(QuizQuestion).where(QuizQuestion.quiz_id == quiz.id).order_by(QuizQuestion.question_index.asc(), QuizQuestion.id.asc())
    ).all()
    if not questions:
        raise HTTPException(status_code=404, detail='quiz not found')

    attempt = UserQuizAttempt(article_id=payload.article_id, correct_count=0, total_count=len(questions), accuracy=0.0)
    db.add(attempt)
    db.flush()

    for question in questions:
        db.add(
            UserQuizAnswer(
                attempt_id=attempt.id,
                question_id=question.id,
                selected_option=None,
                is_correct=False,
            )
        )

    db.commit()
    return success({'attempt_id': attempt.id, 'article_id': payload.article_id, 'accuracy': 0.0})


@router.get('/quiz/attempts/{attempt_id}')
def get_attempt(attempt_id: int, db: Session = Depends(get_db)) -> dict:
    attempt = db.get(UserQuizAttempt, attempt_id)
    if attempt is None:
        raise HTTPException(status_code=404, detail='attempt not found')

    answer_rows = db.execute(
        select(UserQuizAnswer, QuizQuestion)
        .join(QuizQuestion, QuizQuestion.id == UserQuizAnswer.question_id)
        .where(UserQuizAnswer.attempt_id == attempt_id)
        .order_by(QuizQuestion.question_index.asc(), QuizQuestion.id.asc())
    ).all()

    wrong_items = [question.question_index for answer, question in answer_rows if not answer.is_correct]
    return success(
        {
            'attempt_id': attempt.id,
            'correct_count': attempt.correct_count,
            'total_count': attempt.total_count,
            'accuracy': attempt.accuracy,
            'wrong_items': wrong_items,
        }
    )
