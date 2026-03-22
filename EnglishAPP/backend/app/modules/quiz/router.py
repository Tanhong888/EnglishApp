from collections import defaultdict

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.rate_limit import SlidingWindowRateLimiter
from app.core.response import success
from app.db.models import Article, Quiz, QuizOption, QuizQuestion, UserQuizAnswer, UserQuizAttempt
from app.db.session import get_db

router = APIRouter()

QUIZ_SUBMIT_LIMIT_PER_MINUTE = 120
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



def _quiz_submit_rate_limit_keys(request: Request) -> list[str]:
    client_host = request.client.host if request.client else 'unknown'
    return [f'ip:{client_host}']



def _enforce_quiz_submit_rate_limit(keys: list[str]) -> None:
    _sync_quiz_submit_rate_limit_config()
    _quiz_submit_rate_limiter.enforce(keys)



def _get_public_article_or_404(db: Session, article_id: int) -> Article:
    article = db.get(Article, article_id)
    if article is None or not article.is_published:
        raise HTTPException(status_code=404, detail='article not found')
    return article



def _load_quiz_questions(db: Session, article_id: int) -> list[tuple[QuizQuestion, list[QuizOption]]]:
    quiz = db.scalar(select(Quiz).where(Quiz.article_id == article_id))
    if quiz is None:
        return []

    questions = db.scalars(
        select(QuizQuestion)
        .where(QuizQuestion.quiz_id == quiz.id)
        .order_by(QuizQuestion.question_index.asc(), QuizQuestion.id.asc())
    ).all()
    if not questions:
        return []

    question_ids = [q.id for q in questions]
    option_rows = db.scalars(
        select(QuizOption)
        .where(QuizOption.question_id.in_(question_ids))
        .order_by(QuizOption.question_id.asc(), QuizOption.option_index.asc(), QuizOption.id.asc())
    ).all()

    options_by_question: dict[int, list[QuizOption]] = defaultdict(list)
    for option in option_rows:
        options_by_question[option.question_id].append(option)

    return [(question, options_by_question.get(question.id, [])) for question in questions]



def _normalize_selected_option(raw_answer: object, options: list[QuizOption]) -> str | None:
    if raw_answer is None:
        return None

    if isinstance(raw_answer, str):
        normalized = raw_answer.strip()
        return normalized or None

    if isinstance(raw_answer, (int, float)):
        option_id = int(raw_answer)
        by_id = next((opt for opt in options if opt.id == option_id), None)
        if by_id is not None:
            return by_id.content

        by_index = next((opt for opt in options if opt.option_index == option_id), None)
        if by_index is not None:
            return by_index.content

    return str(raw_answer)


@router.get('/articles/{article_id}/quiz')
def get_article_quiz(article_id: int, db: Session = Depends(get_db)) -> dict:
    _get_public_article_or_404(db, article_id)
    question_bundle = _load_quiz_questions(db, article_id)
    if not question_bundle:
        raise HTTPException(status_code=404, detail='quiz not found for article')

    return success(
        {
            'article_id': article_id,
            'questions': [
                {
                    'question_id': question.id,
                    'stem': question.stem,
                    'options': [option.content for option in options],
                }
                for question, options in question_bundle
            ],
        }
    )


@router.post('/quiz/submit')
def submit_quiz(payload: QuizSubmitRequest, request: Request, db: Session = Depends(get_db)) -> dict:
    _enforce_quiz_submit_rate_limit(_quiz_submit_rate_limit_keys(request))
    _get_public_article_or_404(db, payload.article_id)

    question_bundle = _load_quiz_questions(db, payload.article_id)
    if not question_bundle:
        raise HTTPException(status_code=404, detail='quiz not found for article')

    answer_map: dict[int, object] = {}
    for row in payload.answers:
        question_id_raw = row.get('question_id')
        if question_id_raw is None:
            continue
        try:
            question_id = int(question_id_raw)
        except (TypeError, ValueError):
            continue
        answer_map[question_id] = row.get('answer')

    wrong_items: list[int] = []
    correct_count = 0
    answer_rows: list[UserQuizAnswer] = []

    for question, options in question_bundle:
        selected = _normalize_selected_option(answer_map.get(question.id), options)
        correct_option = next((opt for opt in options if opt.is_correct), None)
        is_correct = correct_option is not None and selected == correct_option.content

        if is_correct:
            correct_count += 1
        else:
            wrong_items.append(question.question_index)

        answer_rows.append(
            UserQuizAnswer(
                question_id=question.id,
                selected_option=selected,
                is_correct=is_correct,
            )
        )

    total_count = len(question_bundle)
    accuracy = round(correct_count / total_count, 2) if total_count > 0 else 0.0

    attempt = UserQuizAttempt(
        article_id=payload.article_id,
        correct_count=correct_count,
        total_count=total_count,
        accuracy=accuracy,
    )
    db.add(attempt)
    db.flush()

    for answer in answer_rows:
        answer.attempt_id = attempt.id
    db.add_all(answer_rows)
    db.commit()

    return success({'attempt_id': attempt.id, 'article_id': payload.article_id, 'accuracy': accuracy})


@router.get('/quiz/attempts/{attempt_id}')
def get_attempt(attempt_id: int, db: Session = Depends(get_db)) -> dict:
    attempt = db.get(UserQuizAttempt, attempt_id)
    if attempt is None:
        raise HTTPException(status_code=404, detail='attempt not found')

    wrong_rows = db.execute(
        select(QuizQuestion.question_index)
        .join(UserQuizAnswer, UserQuizAnswer.question_id == QuizQuestion.id)
        .where(UserQuizAnswer.attempt_id == attempt_id, UserQuizAnswer.is_correct.is_(False))
        .order_by(QuizQuestion.question_index.asc(), QuizQuestion.id.asc())
    ).all()

    wrong_items = [row[0] for row in wrong_rows]

    return success(
        {
            'attempt_id': attempt.id,
            'article_id': attempt.article_id,
            'correct_count': attempt.correct_count,
            'total_count': attempt.total_count,
            'accuracy': attempt.accuracy,
            'wrong_items': wrong_items,
        }
    )
