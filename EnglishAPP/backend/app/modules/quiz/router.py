import itertools
import threading

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from app.core.response import success

router = APIRouter()


class QuizSubmitRequest(BaseModel):
    article_id: int
    answers: list[dict]


_QUIZ_BANK: dict[int, list[dict]] = {
    1: [
        {
            'question_id': 101,
            'stem': 'What does the article emphasize about sleep?',
            'options': ['Memory consolidation', 'Faster city traffic', 'Exam registration', 'Plant genetics'],
            'answer': 'Memory consolidation',
        },
        {
            'question_id': 102,
            'stem': 'Which behavior is linked with better performance in the article?',
            'options': ['Staying up late daily', 'Better sleep quality', 'Skipping breakfast', 'Longer social media use'],
            'answer': 'Better sleep quality',
        },
        {
            'question_id': 103,
            'stem': 'The article mainly belongs to which topic?',
            'options': ['Health', 'Finance', 'History', 'Travel'],
            'answer': 'Health',
        },
    ],
    2: [
        {
            'question_id': 201,
            'stem': 'Urban trees can directly improve what?',
            'options': ['Air quality', 'Wi-Fi speed', 'Housing price policy', 'Road tolls'],
            'answer': 'Air quality',
        },
        {
            'question_id': 202,
            'stem': 'Which benefit is mentioned for city residents?',
            'options': ['Mental health support', 'Free public transport', 'Higher taxes', 'Longer workdays'],
            'answer': 'Mental health support',
        },
        {
            'question_id': 203,
            'stem': 'Trees in dense cities also help with:',
            'options': ['Noise reduction', 'Exam grading', 'Cloud storage', 'Flight delays'],
            'answer': 'Noise reduction',
        },
    ],
    3: [
        {
            'question_id': 301,
            'stem': 'The article discusses AI and which social concern?',
            'options': ['Education equity', 'Movie tickets', 'Sports ranking', 'Restaurant tips'],
            'answer': 'Education equity',
        },
        {
            'question_id': 302,
            'stem': 'In this context, equity most closely means:',
            'options': ['Fair access', 'Higher difficulty', 'Faster machines', 'Lower attendance'],
            'answer': 'Fair access',
        },
        {
            'question_id': 303,
            'stem': 'Which group is most likely to benefit from equitable AI education tools?',
            'options': ['Underserved learners', 'Only engineers', 'Only teachers', 'Only administrators'],
            'answer': 'Underserved learners',
        },
    ],
}

_ATTEMPT_ID = itertools.count(7001)
_ATTEMPT_STORE: dict[int, dict] = {}
_ATTEMPT_LOCK = threading.Lock()


def _question_public_view(question: dict) -> dict:
    return {
        'question_id': question['question_id'],
        'stem': question['stem'],
        'options': question['options'],
    }


@router.get('/articles/{article_id}/quiz')
def get_article_quiz(article_id: int) -> dict:
    questions = _QUIZ_BANK.get(article_id)
    if not questions:
        raise HTTPException(status_code=404, detail='quiz not found for article')

    return success(
        {
            'article_id': article_id,
            'questions': [_question_public_view(question) for question in questions],
        }
    )


@router.post('/quiz/submit')
def submit_quiz(payload: QuizSubmitRequest) -> dict:
    questions = _QUIZ_BANK.get(payload.article_id)
    if not questions:
        raise HTTPException(status_code=404, detail='quiz not found for article')

    answer_map: dict[int, str] = {}
    for row in payload.answers:
        question_id_raw = row.get('question_id')
        answer_raw = row.get('answer')
        if question_id_raw is None or answer_raw is None:
            continue
        try:
            answer_map[int(question_id_raw)] = str(answer_raw)
        except (TypeError, ValueError):
            continue

    wrong_items: list[int] = []
    correct_count = 0
    for idx, question in enumerate(questions, start=1):
        selected = answer_map.get(question['question_id'])
        if selected == question['answer']:
            correct_count += 1
        else:
            wrong_items.append(idx)

    total_count = len(questions)
    accuracy = round(correct_count / total_count, 2) if total_count > 0 else 0.0

    with _ATTEMPT_LOCK:
        attempt_id = next(_ATTEMPT_ID)
        _ATTEMPT_STORE[attempt_id] = {
            'attempt_id': attempt_id,
            'article_id': payload.article_id,
            'correct_count': correct_count,
            'total_count': total_count,
            'accuracy': accuracy,
            'wrong_items': wrong_items,
        }

    return success({'attempt_id': attempt_id, 'article_id': payload.article_id, 'accuracy': accuracy})


@router.get('/quiz/attempts/{attempt_id}')
def get_attempt(attempt_id: int) -> dict:
    attempt = _ATTEMPT_STORE.get(attempt_id)
    if attempt is None:
        raise HTTPException(status_code=404, detail='attempt not found')
    return success(attempt)
