"""
Authentication roles (keep in sync with "auth_roles" table).
"""

# MC_REWRITE_TO_PYTHON: make into an enum?

# Do everything, including editing users
ADMIN = 'admin'

# Read-only access to admin interface
ADMIN_READONLY = 'admin-readonly'

# Add / edit media; includes feeds
MEDIA_EDIT = 'media-edit'

# Add / edit stories
STORIES_EDIT = 'stories-edit'

# Topic mapper; includes media and story editing
TM = 'tm'

# topic mapper; excludes media and story editing
TM_READONLY = 'tm-readonly'

# Access to the stories API
STORIES_API = 'stories-api'

# Access to the /search pages
SEARCH = 'search'

# roles that are allows to queue a topic into the 'mc' queue instead of the 'public' queue
TOPIC_MC_QUEUE_ROLES = [ADMIN, ADMIN_READONLY, MEDIA_EDIT, STORIES_EDIT, TM]
