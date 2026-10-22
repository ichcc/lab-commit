bind = "0.0.0.0:8080"
workers = 1
threads = 8
accesslog = "-"


def post_worker_init(worker):
    from app import start_poller

    start_poller()
