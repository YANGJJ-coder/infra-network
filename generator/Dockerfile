FROM python:3.13-alpine@sha256:399babc8b49529dabfd9c922f2b5eea81d611e4512e3ed250d75bd2e7683f4b0

WORKDIR /app
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt
COPY config_generator.py ./

EXPOSE 3011
ENTRYPOINT ["python", "/app/config_generator.py"]
