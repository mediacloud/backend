from temporal.workflow import WorkflowClient

from mediawords.util.network import wait_for_tcp_port_to_open


def workflow_client(namespace: str = 'DEFAULT') -> WorkflowClient:
    """
    Connect to Temporal server and return its client.

    :param namespace: Namespace to connect to.
    :return: WorkflowClient instance.
    """

    host = 'temporal-server'
    port = 7233

    # It's super lame to wait for this port to open, but the Python SDK seems to fail otherwise
    wait_for_tcp_port_to_open(hostname=host, port=port)

    client = WorkflowClient.new_client(host=host, port=port, namespace=namespace)

    return client
