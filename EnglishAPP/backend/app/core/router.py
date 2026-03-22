from fastapi import APIRouter

from app.modules.analysis.router import router as analysis_router
from app.modules.analytics.router import router as analytics_router
from app.modules.auth.router import router as auth_router
from app.modules.content.router import router as content_router
from app.modules.health.router import router as health_router
from app.modules.home.router import router as home_router
from app.modules.me.router import router as me_router
from app.modules.quiz.router import router as quiz_router
from app.modules.reading.router import router as reading_router
from app.modules.users.router import router as users_router
from app.modules.vocab.router import router as vocab_router
from app.modules.words.router import router as words_router

api_router = APIRouter()
api_router.include_router(health_router, tags=['health'])
api_router.include_router(auth_router, prefix='/auth', tags=['auth'])
api_router.include_router(users_router, prefix='/users', tags=['users'])
api_router.include_router(home_router, prefix='/home', tags=['home'])
api_router.include_router(content_router, prefix='/articles', tags=['content'])
api_router.include_router(reading_router, prefix='/reading', tags=['reading'])
api_router.include_router(vocab_router, prefix='/vocab', tags=['vocab'])
api_router.include_router(words_router, prefix='/words', tags=['words'])
api_router.include_router(analysis_router, prefix='/articles', tags=['analysis'])
api_router.include_router(analytics_router, prefix='/analytics', tags=['analytics'])
api_router.include_router(quiz_router, tags=['quiz'])
api_router.include_router(me_router, prefix='/me', tags=['me'])

