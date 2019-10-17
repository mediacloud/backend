import datetime
from typing import List, Optional

from mediawords.util.perl import decode_object_from_bytes_if_needed

from webapp.auth.password import validate_new_password


class McAuthUserException(Exception):
    """BaseUser exception."""
    pass


class Resources(object):
    """User's resources (either the resource limits or the counts of resources used up so far)."""

    __slots__ = [
        '__weekly_requests',
        '__weekly_requested_items',
        '__max_topic_stories',
    ]

    def __init__(self,
                 weekly_requests: Optional[int],
                 weekly_requested_items: Optional[int],
                 max_topic_stories: Optional[int]):

        if isinstance(weekly_requests, bytes):
            weekly_requests = decode_object_from_bytes_if_needed(weekly_requests)
        if isinstance(weekly_requested_items, bytes):
            weekly_requested_items = decode_object_from_bytes_if_needed(weekly_requested_items)
        if isinstance(max_topic_stories, bytes):
            max_topic_stories = decode_object_from_bytes_if_needed(max_topic_stories)

        self.__weekly_requests = int(weekly_requests)
        self.__weekly_requested_items = int(weekly_requested_items)
        self.__max_topic_stories = int(max_topic_stories)

    def weekly_requests(self) -> Optional[int]:
        return self.__weekly_requests

    def weekly_requested_items(self) -> Optional[int]:
        return self.__weekly_requested_items

    def max_topic_stories(self) -> Optional[int]:
        return self.__max_topic_stories


class BaseUser(object):
    """Base user class."""

    # MC_REWRITE_TO_PYTHON: convert the following into @properties after the rewrite (Inline::Python doesn't play well
    # with those)

    __slots__ = [
        '__email',
        '__full_name',
        '__notes',
        '__active',
        '__has_consented',
        '__resource_limits',
    ]

    def __init__(self,
                 email: str,
                 full_name: Optional[str] = None,
                 notes: Optional[str] = None,
                 active: Optional[bool] = None,
                 has_consented: Optional[bool] = None,
                 resource_limits: Optional[Resources] = None):

        email = decode_object_from_bytes_if_needed(email)
        full_name = decode_object_from_bytes_if_needed(full_name)
        notes = decode_object_from_bytes_if_needed(notes)
        if isinstance(active, bytes):
            active = decode_object_from_bytes_if_needed(active)
        if isinstance(has_consented, bytes):
            has_consented = decode_object_from_bytes_if_needed(has_consented)

        if not email:
            raise McAuthUserException("User email is unset.")

        self.__email = email
        self.__full_name = full_name
        self.__notes = notes
        self.__active = bool(int(active))  # because bool(int('0')) == True
        self.__has_consented = bool(int(has_consented))
        self.__resource_limits = resource_limits

    def email(self) -> str:
        return self.__email.lower()

    def full_name(self) -> Optional[str]:
        return self.__full_name

    def notes(self) -> Optional[str]:
        return self.__notes

    def active(self) -> Optional[bool]:
        return self.__active

    def has_consented(self) -> Optional[bool]:
        return self.__has_consented

    def resource_limits(self) -> Optional[Resources]:
        return self.__resource_limits


class NewOrModifyUser(BaseUser):
    """New or existing user object."""

    __slots__ = [
        '__role_ids',
        '__password',
        '__password_repeat',
    ]

    def __init__(self,
                 email: str,
                 full_name: Optional[str] = None,
                 notes: Optional[str] = None,
                 active: Optional[bool] = None,
                 has_consented: Optional[bool] = None,
                 resource_limits: Optional[Resources] = None,
                 password: Optional[str] = None,
                 password_repeat: Optional[str] = None,
                 role_ids: Optional[List[int]] = None):
        super().__init__(
            email=email,
            full_name=full_name,
            notes=notes,
            active=active,
            has_consented=has_consented,
            resource_limits=resource_limits,
        )

        password = decode_object_from_bytes_if_needed(password)
        password_repeat = decode_object_from_bytes_if_needed(password_repeat)

        if password is not None and password_repeat is not None:
            password_validation_message = validate_new_password(
                email=self.email(),
                password=password,
                password_repeat=password_repeat
            )
            if password_validation_message:
                raise McAuthUserException("Password is invalid: %s" % password_validation_message)

        self.__password = password
        self.__password_repeat = password_repeat
        self.__role_ids = role_ids

    def password(self) -> Optional[str]:
        return self.__password

    def password_repeat(self) -> Optional[str]:
        return self.__password_repeat

    def role_ids(self) -> Optional[List[int]]:
        return self.__role_ids


class ModifyUser(NewOrModifyUser):
    """User object for user to be modified by update_user()."""

    def __init__(self,
                 email: str,
                 full_name: Optional[str] = None,
                 notes: Optional[str] = None,
                 active: Optional[bool] = None,
                 has_consented: Optional[bool] = None,
                 resource_limits: Optional[Resources] = None,
                 password: Optional[str] = None,
                 password_repeat: Optional[str] = None,
                 role_ids: Optional[List[int]] = None):

        if role_ids is not None:
            if not isinstance(role_ids, list):
                raise McAuthUserException("List of role IDs is not an array.")

        # Don't require anything but email to be set -- if undef, values won't be changed

        super().__init__(
            email=email,
            full_name=full_name,
            notes=notes,
            active=active,
            has_consented=has_consented,
            resource_limits=resource_limits,
            password=password,
            password_repeat=password_repeat,
            role_ids=role_ids,
        )


class NewUser(NewOrModifyUser):
    """User object for user to be created by add_user()."""

    __slots__ = [
        '__subscribe_to_newsletter',
        '__activation_url',
    ]

    def __init__(self,
                 email: str,
                 full_name: Optional[str] = None,
                 notes: Optional[str] = None,
                 active: Optional[bool] = None,
                 has_consented: Optional[bool] = None,
                 resource_limits: Optional[Resources] = None,
                 password: Optional[str] = None,
                 password_repeat: Optional[str] = None,
                 role_ids: Optional[List[int]] = None,
                 subscribe_to_newsletter: Optional[bool] = None,
                 activation_url: Optional[str] = None):

        if isinstance(has_consented, bytes):
            has_consented = decode_object_from_bytes_if_needed(has_consented)

        if not full_name:
            raise McAuthUserException("User full name is unset.")

        if has_consented is None:
            raise McAuthUserException("User consent is unset.")

        if notes is None:
            raise McAuthUserException("User notes are undefined (should be at least an empty string).")

        if not isinstance(role_ids, list):
            raise McAuthUserException("List of role IDs is not an array.")

        if not password:
            raise McAuthUserException("Password is unset.")

        if not password_repeat:
            raise McAuthUserException("Password repeat is unset.")

        # Password will be verified by ::NewOrModifyUser

        # Either activate the user right away, or make it inactive and send out an email with activation link
        if (active and activation_url) or (not active and not activation_url):
            raise McAuthUserException("Either make the user active or set the activation URL.")

        super().__init__(
            email=email,
            full_name=full_name,
            notes=notes,
            active=active,
            has_consented=has_consented,
            resource_limits=resource_limits,
            password=password,
            password_repeat=password_repeat,
            role_ids=role_ids,
        )

        if isinstance(subscribe_to_newsletter, bytes):
            subscribe_to_newsletter = decode_object_from_bytes_if_needed(subscribe_to_newsletter)
        subscribe_to_newsletter = bool(int(subscribe_to_newsletter or 0))

        activation_url = decode_object_from_bytes_if_needed(activation_url)

        self.__subscribe_to_newsletter = subscribe_to_newsletter
        self.__activation_url = activation_url

    def subscribe_to_newsletter(self) -> Optional[bool]:
        return self.__subscribe_to_newsletter

    def activation_url(self) -> Optional[str]:
        return self.__activation_url


class APIKey(object):
    """Current user API key."""

    __slots__ = [
        '__api_key',
        '__ip_address',
    ]

    def __init__(self, api_key: str, ip_address: Optional[str] = None):
        api_key = decode_object_from_bytes_if_needed(api_key)
        ip_address = decode_object_from_bytes_if_needed(ip_address)

        if not api_key:
            raise McAuthUserException("API key is unset.")

        self.__api_key = api_key
        self.__ip_address = ip_address

    def api_key(self) -> str:
        return self.__api_key

    def ip_address(self) -> Optional[str]:
        return self.__ip_address


class Role(object):
    """Current user role."""

    __slots__ = [
        '__role_id',
        '__role_name',
    ]

    def __init__(self, role_id: int, role_name: str):
        if isinstance(role_id, bytes):
            role_id = decode_object_from_bytes_if_needed(role_id)
        role_name = decode_object_from_bytes_if_needed(role_name)

        if not role_id:
            raise McAuthUserException("Role ID is unset.")
        if not role_name:
            raise McAuthUserException("Role name is unset.")

        self.__role_id = role_id
        self.__role_name = role_name

    def role_id(self) -> int:
        return self.__role_id

    def role_name(self) -> str:
        return self.__role_name


class CurrentUser(BaseUser):
    """User object for user returned by user_info()."""

    __slots__ = [
        '__user_id',
        '__password_hash',
        '__api_keys',
        '__roles',
        '__created_timestamp',
        '__used_resources',

        # Set by constructor
        '__global_api_key',

        '__ip_addresses_to_api_keys',
        '__roles_to_role_ids',
    ]

    def __init__(self,
                 email: str,
                 full_name: str,
                 notes: str,
                 active: bool,
                 has_consented: bool,
                 resource_limits: Resources,
                 user_id: int,
                 created_timestamp: int,
                 roles: List[Role],
                 password_hash: str,
                 api_keys: List[APIKey],
                 used_resources: Resources):

        if isinstance(user_id, bytes):
            user_id = decode_object_from_bytes_if_needed(user_id)
        if isinstance(created_timestamp, bytes):
            created_timestamp = decode_object_from_bytes_if_needed(created_timestamp)

        password_hash = decode_object_from_bytes_if_needed(password_hash)

        user_id = int(user_id)
        created_timestamp = int(created_timestamp)

        if not user_id:
            raise McAuthUserException("User's ID is unset.")

        if not full_name:
            raise McAuthUserException("User's full name is unset.")

        if notes is None:
            raise McAuthUserException("User's notes is None (should be at least an empty string).")

        if created_timestamp is None:
            raise McAuthUserException("User's creation timestamp is None.")

        if not isinstance(roles, list):
            raise McAuthUserException("List of roles is not a list.")

        if active is None:
            raise McAuthUserException("'User is active' flag is unset.")

        if not password_hash:
            raise McAuthUserException("Password hash is unset.")

        if not isinstance(api_keys, list):
            raise McAuthUserException("List of API keys is not a list.")

        if resource_limits is None:
            raise McAuthUserException("User resource limits is None.")

        if used_resources is None:
            raise McAuthUserException("User used resources is None.")

        super().__init__(
            email=email,
            full_name=full_name,
            notes=notes,
            active=active,
            has_consented=has_consented,
            resource_limits=resource_limits,
        )

        self.__user_id = user_id
        self.__created_timestamp = created_timestamp
        self.__roles = roles
        self.__password_hash = password_hash
        self.__api_keys = api_keys
        self.__used_resources = used_resources

        self.__ip_addresses_to_api_keys = dict()
        for api_key_object in api_keys:
            if api_key_object.ip_address():
                self.__ip_addresses_to_api_keys[api_key_object.ip_address()] = api_key_object.api_key()
            else:
                self.__global_api_key = api_key_object.api_key()

        self.__roles_to_role_ids = dict()
        for role_object in roles:
            self.__roles_to_role_ids[role_object.role_name()] = role_object.role_id()

    def user_id(self) -> int:
        return self.__user_id

    def created_timestamp(self) -> int:
        return self.__created_timestamp

    def roles(self) -> List[Role]:
        return self.__roles

    def password_hash(self) -> str:
        return self.__password_hash

    def api_keys(self) -> List[APIKey]:
        return self.__api_keys

    def global_api_key(self) -> str:
        return self.__global_api_key

    def used_resources(self) -> Resources:
        return self.__used_resources

    def api_key_for_ip_address(self, ip_address: str) -> Optional[str]:
        ip_address = decode_object_from_bytes_if_needed(ip_address)
        return self.__ip_addresses_to_api_keys.get(ip_address, None)

    def created_date(self) -> str:
        """User's creation date (ISO 8601 format)."""
        created_timestamp = datetime.datetime.utcfromtimestamp(self.created_timestamp())
        return created_timestamp.replace(tzinfo=datetime.timezone.utc).isoformat()

    def has_role(self, role_name: str) -> bool:
        """Return True if role is enabled for user."""
        role_name = decode_object_from_bytes_if_needed(role_name)
        return role_name in self.__roles_to_role_ids

    def role_names(self) -> List[str]:
        """Return a list of role names."""
        return [role.role_name() for role in self.roles()]
