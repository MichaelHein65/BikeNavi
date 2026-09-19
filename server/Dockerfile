FROM python:3.12-slim
WORKDIR /app
COPY requirements.lock pyproject.toml ./
COPY bikenavi ./bikenavi
RUN pip install --no-cache-dir -r requirements.lock && pip install --no-deps . \
    && useradd --uid 10001 --create-home bikenavi
USER bikenavi
EXPOSE 8000
CMD ["uvicorn", "bikenavi.main:app", "--host", "0.0.0.0", "--port", "8000", "--no-access-log"]
