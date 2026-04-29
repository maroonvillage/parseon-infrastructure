FROM python:3.11-slim

WORKDIR /app

COPY src/worker.py .

RUN pip install boto3

CMD ["python", "worker.py"]