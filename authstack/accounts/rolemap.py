# Central place to define app-level roles and which Django permissions they imply.
# Pattern supports wildcards * per action prefix.
ROLE_DEFS = {
    "Administrator": {
        "permissions": ["add_*", "change_*", "delete_*", "view_*"],
    },
    "Registrar": {
        "permissions": ["add_user", "change_user", "view_user", "view_*"],
    },
    "Reviewer": {
        "permissions": ["view_*"],
    },
    "Viewer": {
        "permissions": ["view_*"],
    },
}
