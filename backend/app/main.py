import os
from pathlib import Path
from typing import Annotated

from dotenv import load_dotenv
from fastapi import Depends, FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware

from app.ai import AIConfigurationError, AIProviderError, InvoiceDraftService
from app.schemas import InvoiceDraft, InvoiceDraftRequest

load_dotenv(Path(__file__).resolve().parents[1] / ".env")

app = FastAPI(title="AlvaPay API", version="0.1.0")

allowed_origins = [
    origin.strip()
    for origin in os.getenv("CORS_ORIGINS", "http://localhost:8080").split(",")
    if origin.strip()
]

app.add_middleware(
    CORSMiddleware,
    allow_origins=allowed_origins,
    allow_credentials=False,
    allow_methods=["GET", "POST", "OPTIONS"],
    allow_headers=["Content-Type"],
)


@app.get("/api/health")
def health() -> dict[str, str]:
    return {"status": "ok", "service": "alvapay-api"}


def get_invoice_draft_service() -> InvoiceDraftService:
    return InvoiceDraftService()


@app.post("/api/ai/draft", response_model=InvoiceDraft)
async def create_invoice_draft(
    request: InvoiceDraftRequest,
    service: Annotated[InvoiceDraftService, Depends(get_invoice_draft_service)],
) -> InvoiceDraft:
    try:
        return await service.create_draft(request.text)
    except AIConfigurationError as error:
        raise HTTPException(status_code=503, detail=str(error)) from error
    except AIProviderError as error:
        raise HTTPException(status_code=502, detail=str(error)) from error
