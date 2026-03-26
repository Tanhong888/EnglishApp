from sqlalchemy import delete, select
from sqlalchemy.orm import Session

from app.core.constants import DEMO_USER_ID
from app.core.security import hash_password
from app.db.base import Base
from app.db.article_content_sync import (
    ensure_article_slug,
    ensure_article_source,
    summarize_paragraphs,
    sync_article_content_snapshot,
    sync_reading_progress_completion,
)
from app.db.models import (
    Article,
    ArticleAudioTask,
    ArticleContent,
    ArticleParagraph,
    ArticleSource,
    Quiz,
    QuizOption,
    QuizQuestion,
    SentenceAnalysis,
    User,
    UserArticleFavorite,
    UserQuizAnswer,
    UserQuizAttempt,
    UserReadingProgress,
    UserVocabEntry,
    Word,
)
from app.db.session import engine

DEMO_ARTICLE_SPECS = [{'title': 'How Sleep Shapes Memory',
  'stage_tag': 'cet4',
  'level': 1,
  'topic': 'health',
  'reading_minutes': 6,
  'is_completed': False,
  'audio_status': 'processing',
  'article_audio_url': None,
  'paragraphs': ['Sleep is not simply a passive state of rest. During sleep, the brain actively organizes information '
                 'gathered during the day and strengthens important memories.',
                 'Researchers often describe this process as memory consolidation. Facts, vocabulary, and '
                 'problem-solving strategies can become easier to recall after a full night of high-quality sleep.',
                 'For students, this means that study time and sleep time work together rather than compete with each '
                 "other. Staying up late may create the feeling of working harder, but it can reduce the brain's "
                 'ability to store new knowledge efficiently.',
                 'In daily life, consistent sleep habits are just as important as long sleep duration. Going to bed at '
                 'regular times, limiting screen use before sleep, and creating a calm environment can all support '
                 'better learning performance.']},
 {'title': 'The Science of Urban Trees',
  'stage_tag': 'cet6',
  'level': 2,
  'topic': 'environment',
  'reading_minutes': 8,
  'is_completed': True,
  'audio_status': 'ready',
  'article_audio_url': 'https://example.com/audio-2.mp3',
  'paragraphs': ['Urban trees improve air quality by capturing dust and reducing some pollutants near busy roads. '
                 'Their leaves and branches also provide shade that lowers surface temperatures in hot neighborhoods.',
                 'Scientists have found that green streets are linked to better mental health. People who live near '
                 'trees often report lower stress levels and a stronger sense of comfort in daily life.',
                 'Trees can also reduce noise and support biodiversity. Even small pockets of urban greenery may '
                 'become habitats for birds, insects, and other forms of life that would otherwise disappear from '
                 'dense cities.',
                 'Because land in large cities is limited, planning where to place trees matters. Successful projects '
                 'usually balance environmental benefits, public safety, and long-term maintenance costs.']},
 {'title': 'AI and Education Equity',
  'stage_tag': 'kaoyan',
  'level': 3,
  'topic': 'education',
  'reading_minutes': 9,
  'is_completed': False,
  'audio_status': 'failed',
  'article_audio_url': None,
  'paragraphs': ['Artificial intelligence is entering classrooms through tutoring tools, writing assistants, and '
                 'personalized learning platforms. In theory, these systems can help students receive support at the '
                 'moment they need it.',
                 'However, access is not distributed equally. Some learners have fast internet connections, modern '
                 'devices, and teachers trained to use digital tools well, while others face technical and economic '
                 'barriers every day.',
                 'Education equity means more than offering the same software to everyone. It requires attention to '
                 'language differences, accessibility needs, cost, teacher support, and the social context in which '
                 'students learn.',
                 'If AI tools are designed carefully, they may reduce gaps by giving underserved learners faster '
                 'feedback and more flexible practice opportunities. If they are deployed carelessly, they may simply '
                 'reproduce the same inequalities that already exist.']},
 {'title': 'Why Public Libraries Still Matter',
  'stage_tag': 'cet4',
  'level': 1,
  'topic': 'society',
  'reading_minutes': 6,
  'is_completed': False,
  'audio_status': 'pending',
  'article_audio_url': None,
  'paragraphs': ['Public libraries are often seen as quiet places filled with books, but their role in modern '
                 'communities is much broader. Many libraries now provide internet access, study rooms, workshops, and '
                 'support for job seekers.',
                 'For students, libraries offer a stable learning environment that may not always be available at '
                 'home. Free access to information can reduce educational barriers for families with limited '
                 'resources.',
                 'Libraries also serve older adults, migrants, and people who are learning new skills later in life. '
                 'In many cities, they function as safe public spaces where residents can ask questions and connect '
                 'with local services.',
                 'As more information moves online, libraries remain important guides. They help people not only find '
                 'facts, but also judge whether those facts are reliable and worth trusting.']},
 {'title': 'The Hidden Cost of Fast Fashion',
  'stage_tag': 'cet4',
  'level': 2,
  'topic': 'consumption',
  'reading_minutes': 7,
  'is_completed': False,
  'audio_status': 'pending',
  'article_audio_url': None,
  'paragraphs': ['Fast fashion makes trendy clothing cheap and widely available, which is one reason it has become so '
                 'popular. New styles appear quickly, and shoppers are encouraged to buy more items more often.',
                 'However, the low price on a label does not reflect the full environmental cost. Producing large '
                 'amounts of clothing consumes water, energy, and raw materials, while discarded garments often end up '
                 'in landfills.',
                 'There are also social concerns. In some supply chains, workers face long hours, low wages, and '
                 'unsafe conditions in order to meet constant demand for new products.',
                 'Consumers cannot solve every problem alone, but small choices still matter. Buying fewer items, '
                 'choosing durable materials, and wearing clothes longer can reduce waste and encourage more '
                 'responsible production.']},
 {'title': 'The Psychology of Delayed Gratification',
  'stage_tag': 'cet6',
  'level': 2,
  'topic': 'psychology',
  'reading_minutes': 7,
  'is_completed': False,
  'audio_status': 'pending',
  'article_audio_url': None,
  'paragraphs': ['Delayed gratification refers to the ability to resist an immediate reward in order to gain a larger '
                 'benefit later. This skill is often connected to long-term goals such as saving money, building '
                 'healthy habits, or completing difficult study plans.',
                 'Psychologists note that self-control is not simply a matter of strong will. People make better '
                 'decisions when they reduce temptation, set clear goals, and design routines that support patience.',
                 'For example, a student who turns off phone notifications before studying is not proving moral '
                 'superiority. Instead, that student is shaping the environment so that focused behavior becomes '
                 'easier to maintain.',
                 'The good news is that delayed gratification can improve with practice. Small repeated actions, such '
                 'as keeping promises to oneself, may gradually strengthen confidence and discipline over time.']},
 {'title': 'Can Cities Prepare for Extreme Heat?',
  'stage_tag': 'cet6',
  'level': 3,
  'topic': 'climate',
  'reading_minutes': 8,
  'is_completed': False,
  'audio_status': 'pending',
  'article_audio_url': None,
  'paragraphs': ['Extreme heat is becoming a serious urban challenge as climate change increases the frequency of heat '
                 'waves. In dense cities, concrete and asphalt absorb sunlight during the day and release heat slowly '
                 'at night.',
                 'This pattern creates what experts call the urban heat island effect. Neighborhoods with fewer trees '
                 'and less shade can remain dangerously hot even after sunset, which raises health risks for older '
                 'adults and outdoor workers.',
                 'City governments are testing several responses, including reflective roofs, cooling centers, tree '
                 'planting, and redesigned public spaces. Effective plans combine short-term emergency measures with '
                 'long-term infrastructure changes.',
                 'Preparation also depends on communication. Residents need clear warnings, reliable access to water, '
                 'and practical advice that reaches vulnerable groups before temperatures become life-threatening.']},
 {'title': 'How Satellites Monitor the Ocean',
  'stage_tag': 'kaoyan',
  'level': 3,
  'topic': 'science',
  'reading_minutes': 8,
  'is_completed': False,
  'audio_status': 'pending',
  'article_audio_url': None,
  'paragraphs': ['Satellites allow scientists to observe the ocean on a global scale. From space, researchers can '
                 'track sea surface temperature, algae growth, storm patterns, and changes in ice coverage over time.',
                 'These measurements are valuable because the ocean changes constantly and covers a vast area that '
                 'ships alone cannot monitor efficiently. Satellite data makes it easier to compare regions and '
                 'identify unusual trends quickly.',
                 'However, remote sensing does not replace direct observation. Scientists still need data from ships, '
                 'underwater instruments, and coastal stations to confirm what satellite images suggest.',
                 'When multiple sources are combined, researchers gain a clearer picture of marine systems. This helps '
                 'governments, fishing communities, and climate scientists make better decisions based on timely '
                 'evidence.']},
 {'title': 'The Future of Battery Recycling',
  'stage_tag': 'kaoyan',
  'level': 4,
  'topic': 'technology',
  'reading_minutes': 9,
  'is_completed': False,
  'audio_status': 'pending',
  'article_audio_url': None,
  'paragraphs': ['As electric vehicles and portable electronics become more common, the number of used batteries is '
                 'rising rapidly. This growth has increased attention to battery recycling as both an economic and '
                 'environmental priority.',
                 'Many batteries contain valuable materials such as lithium, nickel, and cobalt. Recovering these '
                 'resources can reduce pressure on mining and strengthen supply chains for future manufacturing.',
                 'Yet recycling is technically difficult. Batteries are designed in different forms, their chemical '
                 'composition varies, and damaged cells can create safety risks during transport and processing.',
                 'Researchers and companies are exploring new methods to make recycling cheaper and more efficient. If '
                 'these efforts succeed, battery recycling may become a key part of a cleaner and more resilient '
                 'energy system.']},
 {'title': 'How Bilingual Brains Switch Attention',
  'stage_tag': 'cet6',
  'level': 2,
  'topic': 'neuroscience',
  'reading_minutes': 7,
  'is_completed': False,
  'audio_status': 'pending',
  'article_audio_url': None,
  'paragraphs': ['Using two languages is not just a communication skill. Bilingual speakers often need to choose one '
                 'language while suppressing another, which requires attention and mental flexibility.',
                 'Researchers study whether this repeated switching strengthens executive control. Some studies '
                 'suggest bilingual experience can support tasks that involve focus, conflict resolution, and rapid '
                 'selection.',
                 'At the same time, scientists are careful not to exaggerate the effect. The benefits are not '
                 'automatic, and they depend on age, proficiency, and daily use of both languages.',
                 'For learners, the main lesson is practical. Language study can shape the mind over time, especially '
                 'when practice is active, frequent, and connected to real situations.']},
 {'title': 'Why Wetlands Protect Coastal Cities',
  'stage_tag': 'cet6',
  'level': 2,
  'topic': 'environment',
  'reading_minutes': 7,
  'is_completed': False,
  'audio_status': 'pending',
  'article_audio_url': None,
  'paragraphs': ['Wetlands are often overlooked because they seem less dramatic than beaches or forests. Yet these '
                 'marshes, mangroves, and tidal flats provide some of the strongest natural protection for coastal '
                 'communities.',
                 'When storms arrive, wetlands can absorb water and reduce wave energy. This slows flooding and lowers '
                 'the pressure placed on roads, homes, and sea walls during extreme weather.',
                 'Wetlands also filter pollution, store carbon, and create habitats for birds, fish, and insects. In '
                 'this way, they support both environmental health and local economies that depend on tourism or '
                 'fishing.',
                 'Protecting wetlands is usually cheaper than rebuilding damaged infrastructure again and again. Many '
                 'experts now argue that restoration should be treated as a serious part of urban planning.']},
 {'title': 'The Economics of Food Waste',
  'stage_tag': 'cet4',
  'level': 2,
  'topic': 'economy',
  'reading_minutes': 7,
  'is_completed': False,
  'audio_status': 'pending',
  'article_audio_url': None,
  'paragraphs': ['Food waste is often discussed as a moral problem, but it is also an economic one. Every meal that is '
                 'thrown away represents lost labor, transport, energy, and storage costs.',
                 'Waste happens at many stages. Crops may be rejected for cosmetic reasons, stores may overorder '
                 'products, and households may buy more than they can use before it spoils.',
                 'The financial losses are large, but the environmental cost is also serious. Wasted food can mean '
                 'wasted water, farmland, and fuel, while landfills produce greenhouse gases as food breaks down.',
                 'Reducing waste requires better forecasting, smarter packaging, and more realistic consumer habits. '
                 'Small improvements across the supply chain can create major savings over time.']},
 {'title': 'Can Exercise Improve Mood?',
  'stage_tag': 'cet4',
  'level': 1,
  'topic': 'health',
  'reading_minutes': 6,
  'is_completed': False,
  'audio_status': 'pending',
  'article_audio_url': None,
  'paragraphs': ['Many people think of exercise mainly as a way to manage weight or build strength. However, regular '
                 'movement can also influence mood, attention, and stress levels in daily life.',
                 'Physical activity increases blood flow and can trigger chemical changes linked to emotional '
                 'well-being. Even a short walk may help some people feel calmer and more alert after a difficult '
                 'morning.',
                 'Exercise is not a complete answer to serious mental health conditions, and it should not replace '
                 'professional support when that support is needed. Still, it can be one useful part of a broader '
                 'routine for self-care.',
                 'The most effective plan is usually the one a person can maintain. Instead of aiming for perfection, '
                 'many health experts encourage people to start small and build consistency first.']},
 {'title': 'How Museums Use Digital Twins',
  'stage_tag': 'kaoyan',
  'level': 3,
  'topic': 'technology',
  'reading_minutes': 8,
  'is_completed': False,
  'audio_status': 'pending',
  'article_audio_url': None,
  'paragraphs': ['A digital twin is a detailed virtual model of a real object or space. Museums are beginning to use '
                 'this technology to study exhibition rooms, preserve artifacts, and improve visitor experiences.',
                 'With sensors and 3D scanning, staff can monitor temperature, light, humidity, and crowd movement '
                 'more precisely. This helps protect fragile collections and identify risks before damage becomes '
                 'severe.',
                 'Digital twins also support planning. Curators can test how a new exhibition layout might affect '
                 'traffic flow, accessibility, or visibility without moving valuable objects repeatedly in the real '
                 'building.',
                 'For the public, these models may eventually create richer online visits and educational tools. '
                 'Still, institutions must balance innovation with cost, data management, and long-term maintenance.']},
 {'title': 'The Rise of Night Trains in Europe',
  'stage_tag': 'cet6',
  'level': 2,
  'topic': 'transport',
  'reading_minutes': 7,
  'is_completed': False,
  'audio_status': 'pending',
  'article_audio_url': None,
  'paragraphs': ['Night trains were once treated as old-fashioned, but they are returning to public discussion in '
                 'Europe. Rising interest in lower-carbon travel has encouraged governments and companies to '
                 'reconsider long-distance rail routes.',
                 'For some travelers, the appeal is practical. A passenger can leave one city in the evening, sleep on '
                 'board, and arrive in another city the next morning without paying for a hotel.',
                 'Night rail is not perfect. Tickets can still be expensive, sleeping conditions vary, and rail '
                 'systems across borders are not always well coordinated.',
                 'Even so, the renewed interest shows how climate concerns can reshape transport choices. If service '
                 'quality improves, night trains may become a serious alternative to short-haul flights on some '
                 'routes.']},
 {'title': 'Why Coral Reefs Need Protection',
  'stage_tag': 'cet4',
  'level': 2,
  'topic': 'ocean',
  'reading_minutes': 7,
  'is_completed': False,
  'audio_status': 'pending',
  'article_audio_url': None,
  'paragraphs': ['Coral reefs cover only a small part of the ocean, but they support an enormous variety of life. Many '
                 'fish, shellfish, and marine plants depend on reef systems during part of their life cycle.',
                 'Reefs also matter to people. They help protect coastlines from waves, support tourism, and provide '
                 'food or income for millions of residents in coastal regions.',
                 'Yet coral reefs are under pressure from warming oceans, pollution, and destructive fishing '
                 'practices. When water becomes too warm, corals can lose the algae that keep them healthy, a process '
                 'known as bleaching.',
                 'Protection requires both local and global action. Better water management can help nearby reefs, but '
                 'long-term survival also depends on limiting climate change and reducing stress on marine '
                 'ecosystems.']},
 {'title': 'The Science of Habit Loops',
  'stage_tag': 'cet6',
  'level': 2,
  'topic': 'psychology',
  'reading_minutes': 7,
  'is_completed': False,
  'audio_status': 'pending',
  'article_audio_url': None,
  'paragraphs': ['Habits often feel automatic, but researchers describe them as loops made of cues, routines, and '
                 'rewards. A familiar signal can trigger a repeated action that the brain has learned to expect.',
                 'This helps explain why habits are difficult to change through motivation alone. If the cue stays the '
                 'same and the reward remains attractive, the old routine can return even after a person makes a '
                 'strong promise.',
                 'Many behavior experts suggest replacing a routine rather than trying to erase it completely. When '
                 'people identify the cue and reward clearly, they can design a new action that meets a similar need.',
                 'This process takes repetition, not just insight. Over time, a better loop can become easier to '
                 'follow because the brain begins to treat it as the new normal.']},
 {'title': 'Can Vertical Farms Feed Cities?',
  'stage_tag': 'kaoyan',
  'level': 3,
  'topic': 'agriculture',
  'reading_minutes': 8,
  'is_completed': False,
  'audio_status': 'pending',
  'article_audio_url': None,
  'paragraphs': ['Vertical farms grow crops indoors in stacked layers, often with carefully controlled light, '
                 'temperature, and water systems. Supporters argue that this model can bring food production closer to '
                 'dense urban populations.',
                 'Because the environment is controlled, these farms can use less water and reduce the need for some '
                 'pesticides. They can also shorten transport distance for vegetables that spoil quickly after '
                 'harvest.',
                 'However, vertical farming faces real limits. Electricity costs are high, not every crop is suitable, '
                 'and building large indoor systems requires significant investment and technical expertise.',
                 'For now, vertical farms are best seen as one tool rather than a complete solution. They may '
                 'complement traditional agriculture, especially for leafy greens and specialty crops in large '
                 'cities.']},
 {'title': 'How Citizen Science Expands Research',
  'stage_tag': 'cet6',
  'level': 3,
  'topic': 'science',
  'reading_minutes': 8,
  'is_completed': False,
  'audio_status': 'pending',
  'article_audio_url': None,
  'paragraphs': ['Citizen science refers to research projects that invite members of the public to collect or classify '
                 'data. Bird counts, water quality checks, and astronomy image reviews are common examples.',
                 'These projects can extend the reach of professional researchers. A small scientific team may gain '
                 'observations from thousands of volunteers across wide geographic areas and long periods of time.',
                 'Public participation also has educational value. People who join a project often learn more about '
                 'scientific methods, uncertainty, and the importance of careful observation.',
                 'Still, strong project design is essential. Volunteers need clear instructions, data must be checked '
                 'for quality, and researchers must communicate results honestly so participants understand how their '
                 'work contributes.']},
 {'title': 'Why Data Privacy Matters to Students',
  'stage_tag': 'cet4',
  'level': 2,
  'topic': 'technology',
  'reading_minutes': 7,
  'is_completed': False,
  'audio_status': 'pending',
  'article_audio_url': None,
  'paragraphs': ['Students use digital tools for homework, exams, reading, and communication every day. As a result, '
                 'schools and technology platforms collect large amounts of personal information, often without '
                 'students fully understanding what is stored.',
                 'Some data collection supports useful services, such as personalized feedback or learning analytics. '
                 'But privacy concerns appear when data is kept too long, shared too widely, or used in ways that are '
                 'not clearly explained.',
                 'Good privacy practice is not only a technical issue. It also depends on trust, informed consent, and '
                 'simple language that users can actually understand before they agree to a service.',
                 'For students, learning about privacy is part of digital literacy. Knowing how to protect passwords, '
                 'review permissions, and question unnecessary data requests can reduce risk over time.']}]

DEMO_SENTENCE_ANALYSIS_SPECS = {'How Sleep Shapes Memory': [{'sentence_index': 1,
                              'sentence': 'Sleep is not simply a passive state of rest.',
                              'translation': 'Sleep is not only passive rest.',
                              'structure': 'subject + linking verb + complement'},
                             {'sentence_index': 2,
                              'sentence': 'For students, this means that study time and sleep time work together '
                                          'rather than compete with each other.',
                              'translation': 'For students, study and sleep should support each other instead of '
                                             'competing.',
                              'structure': 'fronted prepositional phrase + object clause + rather than contrast'}],
 'The Science of Urban Trees': [{'sentence_index': 1,
                                 'sentence': 'Urban trees improve air quality by capturing dust and reducing some '
                                             'pollutants near busy roads.',
                                 'translation': 'Urban trees improve air quality by trapping dust and lowering some '
                                                'pollutants.',
                                 'structure': 'subject + verb + object + by doing phrase'},
                                {'sentence_index': 2,
                                 'sentence': 'Because land in large cities is limited, planning where to place trees '
                                             'matters.',
                                 'translation': 'Because urban land is limited, deciding where to place trees matters.',
                                 'structure': 'reason clause + gerund phrase as subject'}],
 'AI and Education Equity': [{'sentence_index': 1,
                              'sentence': 'Artificial intelligence is entering classrooms through tutoring tools, '
                                          'writing assistants, and personalized learning platforms.',
                              'translation': 'AI is entering classrooms through tutoring tools and personalized '
                                             'platforms.',
                              'structure': 'subject + progressive verb + through phrase'},
                             {'sentence_index': 2,
                              'sentence': 'Education equity means more than offering the same software to everyone.',
                              'translation': 'Education equity means more than giving the same software to all '
                                             'learners.',
                              'structure': 'subject + verb + more than comparison'}],
 'Why Public Libraries Still Matter': [{'sentence_index': 1,
                                        'sentence': 'Many libraries now provide internet access, study rooms, '
                                                    'workshops, and support for job seekers.',
                                        'translation': 'Many libraries now provide internet access, study space, '
                                                       'workshops, and job support.',
                                        'structure': 'subject + verb + parallel objects'},
                                       {'sentence_index': 2,
                                        'sentence': 'They help people not only find facts, but also judge whether '
                                                    'those facts are reliable and worth trusting.',
                                        'translation': 'Libraries help people both find facts and judge whether those '
                                                       'facts are reliable.',
                                        'structure': 'not only but also pattern + whether clause'}],
 'The Hidden Cost of Fast Fashion': [{'sentence_index': 1,
                                      'sentence': 'However, the low price on a label does not reflect the full '
                                                  'environmental cost.',
                                      'translation': 'A low price tag does not show the full environmental cost.',
                                      'structure': 'contrast adverb + subject + negative verb + object'},
                                     {'sentence_index': 2,
                                      'sentence': 'Buying fewer items, choosing durable materials, and wearing clothes '
                                                  'longer can reduce waste and encourage more responsible production.',
                                      'translation': 'Buying less and using clothes longer can reduce waste and '
                                                     'encourage better production.',
                                      'structure': 'parallel gerund subjects + parallel verbs'}],
 'The Psychology of Delayed Gratification': [{'sentence_index': 1,
                                              'sentence': 'Delayed gratification refers to the ability to resist an '
                                                          'immediate reward in order to gain a larger benefit later.',
                                              'translation': 'Delayed gratification means resisting an immediate '
                                                             'reward to gain a larger later benefit.',
                                              'structure': 'subject + refer to + noun phrase + purpose phrase'},
                                             {'sentence_index': 2,
                                              'sentence': 'The good news is that delayed gratification can improve '
                                                          'with practice.',
                                              'translation': 'The good news is that practice can improve delayed '
                                                             'gratification.',
                                              'structure': 'subject + linking verb + that clause'}],
 'Can Cities Prepare for Extreme Heat?': [{'sentence_index': 1,
                                           'sentence': 'Extreme heat is becoming a serious urban challenge as climate '
                                                       'change increases the frequency of heat waves.',
                                           'translation': 'Extreme heat is becoming a major urban challenge as climate '
                                                          'change brings more heat waves.',
                                           'structure': 'main clause + as clause'},
                                          {'sentence_index': 2,
                                           'sentence': 'Effective plans combine short-term emergency measures with '
                                                       'long-term infrastructure changes.',
                                           'translation': 'Good plans combine emergency action with long-term '
                                                          'infrastructure change.',
                                           'structure': 'subject + combine A with B'}],
 'How Satellites Monitor the Ocean': [{'sentence_index': 1,
                                       'sentence': 'Satellites allow scientists to observe the ocean on a global '
                                                   'scale.',
                                       'translation': 'Satellites let scientists observe the ocean on a global scale.',
                                       'structure': 'subject + allow + object + to do'},
                                      {'sentence_index': 2,
                                       'sentence': 'When multiple sources are combined, researchers gain a clearer '
                                                   'picture of marine systems.',
                                       'translation': 'When multiple data sources are combined, researchers understand '
                                                      'marine systems more clearly.',
                                       'structure': 'time clause + main clause'}],
 'The Future of Battery Recycling': [{'sentence_index': 1,
                                      'sentence': 'Recovering these resources can reduce pressure on mining and '
                                                  'strengthen supply chains for future manufacturing.',
                                      'translation': 'Recovering these materials can reduce mining pressure and '
                                                     'strengthen supply chains.',
                                      'structure': 'gerund phrase as subject + parallel verbs'},
                                     {'sentence_index': 2,
                                      'sentence': 'If these efforts succeed, battery recycling may become a key part '
                                                  'of a cleaner and more resilient energy system.',
                                      'translation': 'If these efforts work, battery recycling may become a key part '
                                                     'of a cleaner energy system.',
                                      'structure': 'if clause + modal verb + complement'}],
 'How Bilingual Brains Switch Attention': [{'sentence_index': 1,
                                            'sentence': 'Bilingual speakers often need to choose one language while '
                                                        'suppressing another, which requires attention and mental '
                                                        'flexibility.',
                                            'translation': 'Bilingual speakers often choose one language while '
                                                           'suppressing another, which requires attention and mental '
                                                           'flexibility.',
                                            'structure': 'main clause + while phrase + relative clause'},
                                           {'sentence_index': 2,
                                            'sentence': 'The benefits are not automatic, and they depend on age, '
                                                        'proficiency, and daily use of both languages.',
                                            'translation': 'The benefits are not automatic and depend on age, '
                                                           'proficiency, and daily use.',
                                            'structure': 'negative clause + parallel noun series'}],
 'Why Wetlands Protect Coastal Cities': [{'sentence_index': 1,
                                          'sentence': 'When storms arrive, wetlands can absorb water and reduce wave '
                                                      'energy.',
                                          'translation': 'When storms arrive, wetlands can absorb water and reduce '
                                                         'wave energy.',
                                          'structure': 'time clause + parallel verbs'},
                                         {'sentence_index': 2,
                                          'sentence': 'Many experts now argue that restoration should be treated as a '
                                                      'serious part of urban planning.',
                                          'translation': 'Many experts argue that restoration should be treated as an '
                                                         'important part of urban planning.',
                                          'structure': 'subject + reporting verb + that clause'}],
 'The Economics of Food Waste': [{'sentence_index': 1,
                                  'sentence': 'Every meal that is thrown away represents lost labor, transport, '
                                              'energy, and storage costs.',
                                  'translation': 'Every meal that is thrown away represents lost labor, transport, '
                                                 'energy, and storage costs.',
                                  'structure': 'subject + relative clause + verb + parallel objects'},
                                 {'sentence_index': 2,
                                  'sentence': 'Small improvements across the supply chain can create major savings '
                                              'over time.',
                                  'translation': 'Small improvements across the supply chain can create major savings '
                                                 'over time.',
                                  'structure': 'subject + modal verb + object + time phrase'}],
 'Can Exercise Improve Mood?': [{'sentence_index': 1,
                                 'sentence': 'Regular movement can also influence mood, attention, and stress levels '
                                             'in daily life.',
                                 'translation': 'Regular exercise can influence mood, attention, and stress in daily '
                                                'life.',
                                 'structure': 'subject + modal verb + parallel objects'},
                                {'sentence_index': 2,
                                 'sentence': 'The most effective plan is usually the one a person can maintain.',
                                 'translation': 'The most effective plan is usually the one a person can maintain.',
                                 'structure': 'linking verb + complement + defining clause'}],
 'How Museums Use Digital Twins': [{'sentence_index': 1,
                                    'sentence': 'Museums are beginning to use this technology to study exhibition '
                                                'rooms, preserve artifacts, and improve visitor experiences.',
                                    'translation': 'Museums are starting to use this technology to study rooms, '
                                                   'protect artifacts, and improve visits.',
                                    'structure': 'progressive verb + purpose phrase + parallel verbs'},
                                   {'sentence_index': 2,
                                    'sentence': 'Curators can test how a new exhibition layout might affect traffic '
                                                'flow, accessibility, or visibility without moving valuable objects '
                                                'repeatedly in the real building.',
                                    'translation': 'Curators can test how a new layout might affect traffic flow, '
                                                   'accessibility, or visibility without moving valuable objects many '
                                                   'times.',
                                    'structure': 'subject + modal verb + embedded clause + without phrase'}],
 'The Rise of Night Trains in Europe': [{'sentence_index': 1,
                                         'sentence': 'Rising interest in lower-carbon travel has encouraged '
                                                     'governments and companies to reconsider long-distance rail '
                                                     'routes.',
                                         'translation': 'Growing interest in low-carbon travel has encouraged '
                                                        'governments and companies to reconsider long-distance rail '
                                                        'routes.',
                                         'structure': 'subject + present perfect + object + to do'},
                                        {'sentence_index': 2,
                                         'sentence': 'If service quality improves, night trains may become a serious '
                                                     'alternative to short-haul flights on some routes.',
                                         'translation': 'If service quality improves, night trains may become a '
                                                        'serious alternative to short flights.',
                                         'structure': 'if clause + modal verb + complement'}],
 'Why Coral Reefs Need Protection': [{'sentence_index': 1,
                                      'sentence': 'Coral reefs cover only a small part of the ocean, but they support '
                                                  'an enormous variety of life.',
                                      'translation': 'Coral reefs cover only a small part of the ocean, but they '
                                                     'support great biodiversity.',
                                      'structure': 'contrast clause + verb + object'},
                                     {'sentence_index': 2,
                                      'sentence': 'Protection requires both local and global action.',
                                      'translation': 'Protection requires both local and global action.',
                                      'structure': 'subject + verb + both A and B'}],
 'The Science of Habit Loops': [{'sentence_index': 1,
                                 'sentence': 'Researchers describe habits as loops made of cues, routines, and '
                                             'rewards.',
                                 'translation': 'Researchers describe habits as loops made of cues, routines, and '
                                                'rewards.',
                                 'structure': 'subject + verb + object complement'},
                                {'sentence_index': 2,
                                 'sentence': 'When people identify the cue and reward clearly, they can design a new '
                                             'action that meets a similar need.',
                                 'translation': 'When people identify the cue and reward clearly, they can design a '
                                                'new action that meets a similar need.',
                                 'structure': 'time clause + main clause + relative clause'}],
 'Can Vertical Farms Feed Cities?': [{'sentence_index': 1,
                                      'sentence': 'Vertical farms grow crops indoors in stacked layers, often with '
                                                  'carefully controlled light, temperature, and water systems.',
                                      'translation': 'Vertical farms grow crops indoors in stacked layers with '
                                                     'controlled light, temperature, and water.',
                                      'structure': 'subject + verb + place phrase + with phrase'},
                                     {'sentence_index': 2,
                                      'sentence': 'For now, vertical farms are best seen as one tool rather than a '
                                                  'complete solution.',
                                      'translation': 'For now, vertical farms are best seen as one tool rather than a '
                                                     'complete solution.',
                                      'structure': 'fronted phrase + passive structure + rather than contrast'}],
 'How Citizen Science Expands Research': [{'sentence_index': 1,
                                           'sentence': 'Citizen science refers to research projects that invite '
                                                       'members of the public to collect or classify data.',
                                           'translation': 'Citizen science refers to research projects that invite the '
                                                          'public to collect or classify data.',
                                           'structure': 'subject + refers to + noun phrase + relative clause'},
                                          {'sentence_index': 2,
                                           'sentence': 'A small scientific team may gain observations from thousands '
                                                       'of volunteers across wide geographic areas and long periods of '
                                                       'time.',
                                           'translation': 'A small scientific team may gain observations from '
                                                          'thousands of volunteers across wide areas and long periods.',
                                           'structure': 'subject + modal verb + object + source phrase'}],
 'Why Data Privacy Matters to Students': [{'sentence_index': 1,
                                           'sentence': 'Schools and technology platforms collect large amounts of '
                                                       'personal information, often without students fully '
                                                       'understanding what is stored.',
                                           'translation': 'Schools and technology platforms collect a lot of personal '
                                                          'information, often without students fully understanding '
                                                          'what is stored.',
                                           'structure': 'subject + verb + object + without phrase + object clause'},
                                          {'sentence_index': 2,
                                           'sentence': 'Knowing how to protect passwords, review permissions, and '
                                                       'question unnecessary data requests can reduce risk over time.',
                                           'translation': 'Knowing how to protect passwords, review permissions, and '
                                                          'question unnecessary data requests can reduce risk over '
                                                          'time.',
                                           'structure': 'gerund subject + parallel verbs + modal meaning'}]}

DEMO_QUIZ_BANK = {'How Sleep Shapes Memory': [{'stem': 'What process does sleep help strengthen according to the article?',
                              'options': ['Memory consolidation',
                                          'Traffic control',
                                          'Tree growth',
                                          'Language extinction'],
                              'answer': 'Memory consolidation'},
                             {'stem': 'Why can staying up late be harmful to learning?',
                              'options': ["It reduces the brain's ability to store knowledge",
                                          'It makes books more expensive',
                                          'It weakens library services',
                                          'It lowers city temperatures'],
                              'answer': "It reduces the brain's ability to store knowledge"},
                             {'stem': 'Which habit does the article recommend before sleep?',
                              'options': ['Limiting screen use',
                                          'Skipping dinner',
                                          'Taking longer commutes',
                                          'Buying new clothes'],
                              'answer': 'Limiting screen use'}],
 'The Science of Urban Trees': [{'stem': 'Urban trees improve air quality mainly by doing what?',
                                 'options': ['Capturing dust',
                                             'Increasing traffic',
                                             'Selling equipment',
                                             'Reducing libraries'],
                                 'answer': 'Capturing dust'},
                                {'stem': 'What mental effect is linked to living near trees?',
                                 'options': ['Lower stress levels',
                                             'Higher boredom',
                                             'Fewer memories',
                                             'Longer work hours'],
                                 'answer': 'Lower stress levels'},
                                {'stem': 'Successful tree projects in cities usually balance benefits with what?',
                                 'options': ['Maintenance costs', 'Fashion trends', 'Movie schedules', 'Exam scores'],
                                 'answer': 'Maintenance costs'}],
 'AI and Education Equity': [{'stem': 'The article mainly connects AI with which issue?',
                              'options': ['Education equity', 'Road safety', 'Sports marketing', 'Restaurant design'],
                              'answer': 'Education equity'},
                             {'stem': 'Why is equal access to AI tools difficult?',
                              'options': ['Learners face different technical and economic barriers',
                                          'All teachers reject technology',
                                          'AI only works offline',
                                          'Students dislike feedback'],
                              'answer': 'Learners face different technical and economic barriers'},
                             {'stem': 'What may happen if AI tools are deployed carelessly?',
                              'options': ['Existing inequalities may be repeated',
                                          'All exams will disappear',
                                          'Libraries will close immediately',
                                          'Teachers will stop teaching'],
                              'answer': 'Existing inequalities may be repeated'}],
 'Why Public Libraries Still Matter': [{'stem': 'Besides books, what do many libraries now provide?',
                                        'options': ['Internet access',
                                                    'Private airports',
                                                    'Medical surgery',
                                                    'Factory equipment'],
                                        'answer': 'Internet access'},
                                       {'stem': 'Why are libraries valuable for students?',
                                        'options': ['They provide a stable learning environment',
                                                    'They replace every teacher',
                                                    'They guarantee high salaries',
                                                    'They shorten all exams'],
                                        'answer': 'They provide a stable learning environment'},
                                       {'stem': 'What skill do libraries help people develop in the digital age?',
                                        'options': ['Judging information reliability',
                                                    'Driving faster',
                                                    'Designing satellites',
                                                    'Manufacturing batteries'],
                                        'answer': 'Judging information reliability'}],
 'The Hidden Cost of Fast Fashion': [{'stem': 'Why has fast fashion become popular?',
                                      'options': ['It offers cheap trendy clothing',
                                                  'It improves air quality',
                                                  'It reduces heat waves',
                                                  'It strengthens oceans'],
                                      'answer': 'It offers cheap trendy clothing'},
                                     {'stem': 'Which environmental problem is mentioned in the article?',
                                      'options': ['Discarded garments ending up in landfills',
                                                  'More library noise',
                                                  'Less sleep quality',
                                                  'Fewer satellites'],
                                      'answer': 'Discarded garments ending up in landfills'},
                                     {'stem': 'What is one responsible consumer choice suggested by the article?',
                                      'options': ['Buying fewer items',
                                                  'Replacing clothes weekly',
                                                  'Ignoring material quality',
                                                  'Shopping only at night'],
                                      'answer': 'Buying fewer items'}],
 'The Psychology of Delayed Gratification': [{'stem': 'Delayed gratification means resisting what?',
                                              'options': ['An immediate reward',
                                                          'A public library',
                                                          'A heat wave',
                                                          'A research ship'],
                                              'answer': 'An immediate reward'},
                                             {'stem': 'What can make self-control easier according to psychologists?',
                                              'options': ['Reducing temptation',
                                                          'Buying more devices',
                                                          'Reading less often',
                                                          'Skipping goals'],
                                              'answer': 'Reducing temptation'},
                                             {'stem': 'What message does the article give about delayed gratification?',
                                              'options': ['It can improve with practice',
                                                          'It is fixed at birth',
                                                          'It only matters for children',
                                                          'It is unrelated to habits'],
                                              'answer': 'It can improve with practice'}],
 'Can Cities Prepare for Extreme Heat?': [{'stem': 'What makes extreme heat especially dangerous in dense cities?',
                                           'options': ['The urban heat island effect',
                                                       'More bookstores',
                                                       'Slow internet',
                                                       'Battery recycling'],
                                           'answer': 'The urban heat island effect'},
                                          {'stem': 'Which group is mentioned as especially vulnerable to heat?',
                                           'options': ['Older adults',
                                                       'Only pilots',
                                                       'Only tourists',
                                                       'Only programmers'],
                                           'answer': 'Older adults'},
                                          {'stem': 'What do effective city plans combine?',
                                           'options': ['Emergency measures and infrastructure changes',
                                                       'Trees and airplanes',
                                                       'Libraries and satellites',
                                                       'Phones and clothing'],
                                           'answer': 'Emergency measures and infrastructure changes'}],
 'How Satellites Monitor the Ocean': [{'stem': 'Why are satellites useful for ocean science?',
                                       'options': ['They can observe the ocean on a global scale',
                                                   'They replace all ships forever',
                                                   'They increase fish prices',
                                                   'They reduce library visits'],
                                       'answer': 'They can observe the ocean on a global scale'},
                                      {'stem': 'Why are ships alone not enough for monitoring the ocean?',
                                       'options': ['The ocean is too vast and changes constantly',
                                                   'Ships cannot move at night',
                                                   'Ships cannot measure temperature',
                                                   'Ships only work in cities'],
                                       'answer': 'The ocean is too vast and changes constantly'},
                                      {'stem': 'What is the main advantage of combining satellite data with direct '
                                               'observation?',
                                       'options': ['A clearer picture of marine systems',
                                                   'Cheaper fashion production',
                                                   'Longer workweeks',
                                                   'Less internet access'],
                                       'answer': 'A clearer picture of marine systems'}],
 'The Future of Battery Recycling': [{'stem': 'Why is battery recycling receiving more attention?',
                                      'options': ['Used batteries are increasing rapidly',
                                                  'Cities are getting colder',
                                                  'Libraries are shrinking',
                                                  'Trees need more shade'],
                                      'answer': 'Used batteries are increasing rapidly'},
                                     {'stem': 'Which valuable material is mentioned in batteries?',
                                      'options': ['Lithium', 'Wood', 'Sand', 'Cotton'],
                                      'answer': 'Lithium'},
                                     {'stem': 'What challenge makes battery recycling difficult?',
                                      'options': ['Different battery designs and safety risks',
                                                  'Too many public parks',
                                                  'Lack of online articles',
                                                  'Too much sleep'],
                                      'answer': 'Different battery designs and safety risks'}],
 'How Bilingual Brains Switch Attention': [{'stem': 'What mental skill is closely linked to bilingual language '
                                                    'switching?',
                                            'options': ['Attention and flexibility',
                                                        'Ticket pricing',
                                                        'Ocean depth',
                                                        'Battery repair'],
                                            'answer': 'Attention and flexibility'},
                                           {'stem': 'What do researchers study about bilingual experience?',
                                            'options': ['Whether it supports executive control',
                                                        'Whether it reduces rainfall',
                                                        'Whether it grows coral',
                                                        'Whether it replaces sleep'],
                                            'answer': 'Whether it supports executive control'},
                                           {'stem': 'According to the article, bilingual benefits depend on what?',
                                            'options': ['Age, proficiency, and daily use',
                                                        'Only income level',
                                                        'Only school size',
                                                        'Only city temperature'],
                                            'answer': 'Age, proficiency, and daily use'}],
 'Why Wetlands Protect Coastal Cities': [{'stem': 'How do wetlands help during storms?',
                                          'options': ['They absorb water and reduce wave energy',
                                                      'They increase airport traffic',
                                                      'They raise ticket prices',
                                                      'They power satellites'],
                                          'answer': 'They absorb water and reduce wave energy'},
                                         {'stem': 'Besides flood protection, what else do wetlands do?',
                                          'options': ['Store carbon and support habitats',
                                                      'Print textbooks',
                                                      'Build railroads',
                                                      'Improve phone batteries'],
                                          'answer': 'Store carbon and support habitats'},
                                         {'stem': 'Why do experts support wetland restoration?',
                                          'options': ['It is part of serious urban planning',
                                                      'It makes clothing cheaper',
                                                      'It removes all storms',
                                                      'It closes museums'],
                                          'answer': 'It is part of serious urban planning'}],
 'The Economics of Food Waste': [{'stem': 'Food waste is described as what kind of problem?',
                                  'options': ['Both moral and economic',
                                              'Only artistic',
                                              'Only medical',
                                              'Only political'],
                                  'answer': 'Both moral and economic'},
                                 {'stem': 'Where can food waste happen?',
                                  'options': ['At many stages of the supply chain',
                                              'Only in restaurants',
                                              'Only on farms',
                                              'Only in schools'],
                                  'answer': 'At many stages of the supply chain'},
                                 {'stem': 'What can reducing food waste create over time?',
                                  'options': ['Major savings',
                                              'More traffic noise',
                                              'Longer work hours',
                                              'Less biodiversity'],
                                  'answer': 'Major savings'}],
 'Can Exercise Improve Mood?': [{'stem': 'What does the article say exercise can influence?',
                                 'options': ['Mood, attention, and stress',
                                             'Ocean salinity',
                                             'Library budgets',
                                             'Train timetables'],
                                 'answer': 'Mood, attention, and stress'},
                                {'stem': 'Does the article present exercise as a full replacement for professional '
                                         'support?',
                                 'options': ['No', 'Yes, always', 'Only for children', 'Only in cities'],
                                 'answer': 'No'},
                                {'stem': 'What kind of exercise plan is usually most effective?',
                                 'options': ['One a person can maintain',
                                             'The most expensive one',
                                             'The shortest possible one',
                                             'One with no rest days'],
                                 'answer': 'One a person can maintain'}],
 'How Museums Use Digital Twins': [{'stem': 'What is a digital twin?',
                                    'options': ['A virtual model of a real object or space',
                                                'A new kind of battery',
                                                'A wetland restoration tool',
                                                'A train ticket system'],
                                    'answer': 'A virtual model of a real object or space'},
                                   {'stem': 'Why do museums monitor temperature and humidity?',
                                    'options': ['To protect fragile collections',
                                                'To grow crops indoors',
                                                'To improve coral growth',
                                                'To reduce food waste'],
                                    'answer': 'To protect fragile collections'},
                                   {'stem': 'What can curators test with digital twins?',
                                    'options': ['Exhibition layout effects',
                                                'Ocean currents only',
                                                'Hospital treatments',
                                                'Exam questions only'],
                                    'answer': 'Exhibition layout effects'}],
 'The Rise of Night Trains in Europe': [{'stem': 'Why are night trains receiving new attention?',
                                         'options': ['Interest in lower-carbon travel',
                                                     'Interest in coral reefs',
                                                     'Interest in food packaging',
                                                     'Interest in battery minerals'],
                                         'answer': 'Interest in lower-carbon travel'},
                                        {'stem': 'What is one practical advantage of night trains?',
                                         'options': ['Travelers can sleep while moving between cities',
                                                     'They eliminate all border checks',
                                                     'They never cost money',
                                                     'They carry only freight'],
                                         'answer': 'Travelers can sleep while moving between cities'},
                                        {'stem': 'What could night trains become if service improves?',
                                         'options': ['An alternative to some short-haul flights',
                                                     'A replacement for museums',
                                                     'A form of coastal defense',
                                                     'A tool for crop storage'],
                                         'answer': 'An alternative to some short-haul flights'}],
 'Why Coral Reefs Need Protection': [{'stem': 'Why are coral reefs important in the ocean?',
                                      'options': ['They support a great variety of life',
                                                  'They power satellites',
                                                  'They store train tickets',
                                                  'They cool office buildings'],
                                      'answer': 'They support a great variety of life'},
                                     {'stem': 'What is bleaching?',
                                      'options': ['Corals losing the algae that keep them healthy',
                                                  'A type of museum scan',
                                                  'A rail cleaning process',
                                                  'A battery recycling method'],
                                      'answer': 'Corals losing the algae that keep them healthy'},
                                     {'stem': 'What does reef protection require?',
                                      'options': ['Both local and global action',
                                                  'Only more tourism',
                                                  'Only more fishing boats',
                                                  'Only more classrooms'],
                                      'answer': 'Both local and global action'}],
 'The Science of Habit Loops': [{'stem': 'What three parts make up a habit loop?',
                                 'options': ['Cues, routines, and rewards',
                                             'Books, rooms, and teachers',
                                             'Heat, rain, and snow',
                                             'Salt, sugar, and oil'],
                                 'answer': 'Cues, routines, and rewards'},
                                {'stem': 'Why are habits hard to change?',
                                 'options': ['Old cues and rewards can pull routines back',
                                             'They only exist in childhood',
                                             'They disappear after one mistake',
                                             'They depend on train schedules'],
                                 'answer': 'Old cues and rewards can pull routines back'},
                                {'stem': 'What do many experts suggest instead of erasing a habit?',
                                 'options': ['Replacing the routine',
                                             'Ignoring all cues',
                                             'Avoiding all rewards forever',
                                             'Changing cities immediately'],
                                 'answer': 'Replacing the routine'}],
 'Can Vertical Farms Feed Cities?': [{'stem': 'Where do vertical farms grow crops?',
                                      'options': ['Indoors in stacked layers',
                                                  'Only in deserts',
                                                  'Only on ships',
                                                  'Only in museums'],
                                      'answer': 'Indoors in stacked layers'},
                                     {'stem': 'What is one advantage of vertical farms?',
                                      'options': ['They can use less water',
                                                  'They remove all electricity costs',
                                                  'They grow every crop easily',
                                                  'They end climate change'],
                                      'answer': 'They can use less water'},
                                     {'stem': 'How does the article describe vertical farms today?',
                                      'options': ['One tool rather than a complete solution',
                                                  'The only future of farming',
                                                  'A failed idea with no value',
                                                  'A replacement for wetlands'],
                                      'answer': 'One tool rather than a complete solution'}],
 'How Citizen Science Expands Research': [{'stem': 'What is citizen science?',
                                           'options': ['Research that involves public participation',
                                                       'Private investment in railroads',
                                                       'A type of exercise plan',
                                                       'A form of data deletion'],
                                           'answer': 'Research that involves public participation'},
                                          {'stem': 'Why do researchers use citizen science projects?',
                                           'options': ['To gather data across wider areas and longer times',
                                                       'To eliminate all uncertainty',
                                                       'To avoid checking data quality',
                                                       'To stop publishing results'],
                                           'answer': 'To gather data across wider areas and longer times'},
                                          {'stem': 'What is necessary for strong citizen science design?',
                                           'options': ['Clear instructions and data checks',
                                                       'Only expensive equipment',
                                                       'Only professional astronomers',
                                                       'No communication with volunteers'],
                                           'answer': 'Clear instructions and data checks'}],
 'Why Data Privacy Matters to Students': [{'stem': 'Why do schools and platforms hold student data?',
                                           'options': ['Students use digital tools every day',
                                                       'Students never use technology',
                                                       'Only teachers create data',
                                                       'Only libraries store accounts'],
                                           'answer': 'Students use digital tools every day'},
                                          {'stem': 'When do privacy concerns grow?',
                                           'options': ['When data is kept too long or shared too widely',
                                                       'When passwords are strong',
                                                       'When users read policy pages',
                                                       'When storage is reduced'],
                                           'answer': 'When data is kept too long or shared too widely'},
                                          {'stem': 'What is part of digital literacy for students?',
                                           'options': ['Reviewing permissions and questioning unnecessary requests',
                                                       'Ignoring all updates',
                                                       'Sharing every password',
                                                       'Deleting every app immediately'],
                                           'answer': 'Reviewing permissions and questioning unnecessary requests'}]}

DEMO_WORD_SPECS = [
    {'lemma': 'consolidate', 'phonetic': '\u006b\u0259n\u02c8s\u0251\u02d0l\u026ade\u026at', 'pos': 'vt.', 'meaning_cn': '\u5de9\u56fa'},
    {'lemma': 'equity', 'phonetic': '\u02c8ekw\u026ati', 'pos': 'n.', 'meaning_cn': '\u516c\u5e73'},
]

MANUAL_TEST_ARTICLE_TITLE_PREFIXES = (
    '[tts-fail] Audio Failure Workflow Article',
    'Admin Published Article',
    'Admin Content Pipeline Article',
    'Audio Ready Workflow Article',
    'Snapshot Source Article',
    'AI Research Update ',
    'Imported RSS Article ',
    'Climate Policy Brief ',
)


def init_db() -> None:
    Base.metadata.create_all(bind=engine)



def _ensure_demo_user(db: Session) -> User:
    user = db.scalar(select(User).where(User.id == DEMO_USER_ID))
    if user is None:
        user = User(
            id=DEMO_USER_ID,
            email='demo@englishapp.dev',
            password_hash=hash_password('Passw0rd!'),
            nickname='demo_user',
            target='cet4',
            is_active=True,
        )
        db.add(user)
        db.flush()
    return user



def _upsert_demo_articles(db: Session) -> dict[str, Article]:
    titles = [spec['title'] for spec in DEMO_ARTICLE_SPECS]
    existing_articles = db.scalars(select(Article).where(Article.title.in_(titles))).all()
    article_by_title = {article.title: article for article in existing_articles}

    for spec in DEMO_ARTICLE_SPECS:
        article = article_by_title.get(spec['title'])
        if article is None:
            article = Article(
                title=spec['title'],
                slug=None,
                stage_tag=spec['stage_tag'],
                level=spec['level'],
                topic=spec['topic'],
                summary=None,
                reading_minutes=spec['reading_minutes'],
                status='published',
                source_url=None,
                is_completed=spec['is_completed'],
                audio_status=spec['audio_status'],
                article_audio_url=spec['article_audio_url'],
                is_published=True,
            )
            db.add(article)
            db.flush()
            article_by_title[article.title] = article
        else:
            article.stage_tag = spec['stage_tag']
            article.level = spec['level']
            article.topic = spec['topic']
            article.reading_minutes = spec['reading_minutes']
            article.status = 'published'
            article.is_completed = spec['is_completed']
            article.audio_status = spec['audio_status']
            article.article_audio_url = spec['article_audio_url']
            article.is_published = True

        existing_paragraphs = db.scalars(
            select(ArticleParagraph)
            .where(ArticleParagraph.article_id == article.id)
            .order_by(ArticleParagraph.paragraph_index.asc())
        ).all()
        paragraph_by_index = {paragraph.paragraph_index: paragraph for paragraph in existing_paragraphs}
        desired_indices = set()

        for paragraph_index, text in enumerate(spec['paragraphs'], start=1):
            desired_indices.add(paragraph_index)
            paragraph = paragraph_by_index.get(paragraph_index)
            if paragraph is None:
                db.add(
                    ArticleParagraph(
                        article_id=article.id,
                        paragraph_index=paragraph_index,
                        text=text,
                    )
                )
            else:
                paragraph.text = text

        for paragraph in existing_paragraphs:
            if paragraph.paragraph_index not in desired_indices:
                db.delete(paragraph)

        ensure_article_slug(db, article)
        article.summary = summarize_paragraphs(spec['paragraphs'])
        ensure_article_source(
            db,
            article=article,
            source_type='seed',
            source_name='demo_seed',
            source_url=article.source_url,
        )
        sync_article_content_snapshot(db, article=article, paragraphs=spec['paragraphs'])

    db.flush()
    return article_by_title



def _purge_manual_test_articles(db: Session) -> None:
    article_rows = db.execute(select(Article.id, Article.title)).all()
    article_ids = [
        article_id
        for article_id, title in article_rows
        if any(title.startswith(prefix) for prefix in MANUAL_TEST_ARTICLE_TITLE_PREFIXES)
    ]
    if not article_ids:
        return

    quiz_ids = db.scalars(select(Quiz.id).where(Quiz.article_id.in_(article_ids))).all()
    question_ids = db.scalars(select(QuizQuestion.id).where(QuizQuestion.quiz_id.in_(quiz_ids))).all() if quiz_ids else []
    attempt_ids = db.scalars(select(UserQuizAttempt.id).where(UserQuizAttempt.article_id.in_(article_ids))).all()

    if question_ids:
        db.execute(delete(QuizOption).where(QuizOption.question_id.in_(question_ids)))
    if attempt_ids:
        db.execute(delete(UserQuizAnswer).where(UserQuizAnswer.attempt_id.in_(attempt_ids)))

    db.execute(delete(UserArticleFavorite).where(UserArticleFavorite.article_id.in_(article_ids)))
    db.execute(delete(UserReadingProgress).where(UserReadingProgress.article_id.in_(article_ids)))
    db.execute(delete(UserVocabEntry).where(UserVocabEntry.source_article_id.in_(article_ids)))
    db.execute(delete(SentenceAnalysis).where(SentenceAnalysis.article_id.in_(article_ids)))
    db.execute(delete(ArticleParagraph).where(ArticleParagraph.article_id.in_(article_ids)))
    db.execute(delete(ArticleContent).where(ArticleContent.article_id.in_(article_ids)))
    db.execute(delete(ArticleAudioTask).where(ArticleAudioTask.article_id.in_(article_ids)))
    db.execute(delete(ArticleSource).where(ArticleSource.article_id.in_(article_ids)))

    if question_ids:
        db.execute(delete(QuizQuestion).where(QuizQuestion.id.in_(question_ids)))
    if quiz_ids:
        db.execute(delete(Quiz).where(Quiz.id.in_(quiz_ids)))
    if attempt_ids:
        db.execute(delete(UserQuizAttempt).where(UserQuizAttempt.id.in_(attempt_ids)))

    db.execute(delete(Article).where(Article.id.in_(article_ids)))

def _upsert_demo_words(db: Session) -> dict[str, Word]:
    lemmas = [spec['lemma'] for spec in DEMO_WORD_SPECS]
    existing_words = db.scalars(select(Word).where(Word.lemma.in_(lemmas))).all()
    word_by_lemma = {word.lemma: word for word in existing_words}

    for spec in DEMO_WORD_SPECS:
        word = word_by_lemma.get(spec['lemma'])
        if word is None:
            word = Word(**spec)
            db.add(word)
            db.flush()
            word_by_lemma[word.lemma] = word
        else:
            word.phonetic = spec['phonetic']
            word.pos = spec['pos']
            word.meaning_cn = spec['meaning_cn']

    db.flush()
    return word_by_lemma



def _ensure_demo_learning_data(db: Session, article_by_title: dict[str, Article], word_by_lemma: dict[str, Word]) -> None:
    progress_specs = [
        ('The Science of Urban Trees', 2),
        ('How Sleep Shapes Memory', 1),
    ]
    for title, paragraph_index in progress_specs:
        article = article_by_title[title]
        existing = db.scalar(
            select(UserReadingProgress).where(
                UserReadingProgress.user_id == DEMO_USER_ID,
                UserReadingProgress.article_id == article.id,
            )
        )
        if existing is None:
            existing = UserReadingProgress(
                user_id=DEMO_USER_ID,
                article_id=article.id,
                paragraph_index=paragraph_index,
            )
            db.add(existing)

        sync_reading_progress_completion(
            db,
            progress=existing,
            article=article,
            completed_at_fallback=existing.last_read_at,
        )

    favorite_article = article_by_title['How Sleep Shapes Memory']
    favorite = db.scalar(
        select(UserArticleFavorite).where(
            UserArticleFavorite.user_id == DEMO_USER_ID,
            UserArticleFavorite.article_id == favorite_article.id,
        )
    )
    if favorite is None:
        db.add(UserArticleFavorite(user_id=DEMO_USER_ID, article_id=favorite_article.id, is_favorited=True))

    vocab_specs = [
        ('consolidate', 'How Sleep Shapes Memory', False),
        ('consolidate', 'The Science of Urban Trees', False),
        ('equity', 'AI and Education Equity', True),
    ]
    for lemma, article_title, mastered in vocab_specs:
        article = article_by_title[article_title]
        word = word_by_lemma[lemma]
        entry = db.scalar(
            select(UserVocabEntry).where(
                UserVocabEntry.user_id == DEMO_USER_ID,
                UserVocabEntry.word_id == word.id,
                UserVocabEntry.source_article_id == article.id,
            )
        )
        if entry is None:
            db.add(
                UserVocabEntry(
                    user_id=DEMO_USER_ID,
                    word_id=word.id,
                    source_article_id=article.id,
                    mastered=mastered,
                )
            )



def _replace_sentence_analyses_for_article(db: Session, article_id: int, items: list[dict]) -> None:
    db.execute(delete(SentenceAnalysis).where(SentenceAnalysis.article_id == article_id))
    for item in items:
        db.add(
            SentenceAnalysis(
                article_id=article_id,
                sentence_index=item['sentence_index'],
                sentence=item['sentence'],
                translation=item['translation'],
                structure=item['structure'],
            )
        )



def _seed_sentence_analyses(db: Session) -> None:
    titles = list(DEMO_SENTENCE_ANALYSIS_SPECS.keys())
    articles = db.scalars(select(Article).where(Article.title.in_(titles))).all()
    article_by_title = {article.title: article for article in articles}

    for title, items in DEMO_SENTENCE_ANALYSIS_SPECS.items():
        article = article_by_title.get(title)
        if article is None:
            continue
        _replace_sentence_analyses_for_article(db, article.id, items)

    db.commit()



def _replace_quiz_for_article(db: Session, article_id: int, questions: list[dict]) -> None:
    existing_quizzes = db.scalars(select(Quiz).where(Quiz.article_id == article_id)).all()
    existing_quiz_ids = [quiz.id for quiz in existing_quizzes]
    if existing_quiz_ids:
        existing_question_ids = db.scalars(select(QuizQuestion.id).where(QuizQuestion.quiz_id.in_(existing_quiz_ids))).all()
        if existing_question_ids:
            db.execute(delete(QuizOption).where(QuizOption.question_id.in_(existing_question_ids)))
            db.execute(delete(QuizQuestion).where(QuizQuestion.id.in_(existing_question_ids)))
        db.execute(delete(Quiz).where(Quiz.id.in_(existing_quiz_ids)))

    quiz = Quiz(article_id=article_id)
    db.add(quiz)
    db.flush()

    for question_index, question_spec in enumerate(questions, start=1):
        question = QuizQuestion(
            quiz_id=quiz.id,
            question_index=question_index,
            stem=question_spec['stem'],
        )
        db.add(question)
        db.flush()

        for option_index, option_text in enumerate(question_spec['options'], start=1):
            db.add(
                QuizOption(
                    question_id=question.id,
                    option_index=option_index,
                    content=option_text,
                    is_correct=(option_text == question_spec['answer']),
                )
            )



def _seed_quizzes(db: Session) -> None:
    titles = list(DEMO_QUIZ_BANK.keys())
    articles = db.scalars(select(Article).where(Article.title.in_(titles))).all()
    article_by_title = {article.title: article for article in articles}

    for title, questions in DEMO_QUIZ_BANK.items():
        article = article_by_title.get(title)
        if article is None:
            continue
        _replace_quiz_for_article(db, article.id, questions)

    db.commit()



def seed_db(db: Session) -> None:
    _purge_manual_test_articles(db)
    _ensure_demo_user(db)
    article_by_title = _upsert_demo_articles(db)
    word_by_lemma = _upsert_demo_words(db)
    _ensure_demo_learning_data(db, article_by_title, word_by_lemma)
    db.commit()
    _seed_sentence_analyses(db)
    _seed_quizzes(db)

