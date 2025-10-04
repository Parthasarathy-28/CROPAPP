from fastapi import FastAPI, Depends
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import List
from sqlalchemy import create_engine, Column, Integer, Float, String
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker, Session

# ----------------------
# Database Setup (SQLite)
# ----------------------
DATABASE_URL = "sqlite:///./recommendations.db"

engine = create_engine(DATABASE_URL, connect_args={"check_same_thread": False})
SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False)
Base = declarative_base()

class RecommendationDB(Base):
    __tablename__ = "recommendations"
    id = Column(Integer, primary_key=True, index=True)
    ph = Column(Float)
    moisture = Column(Float)
    rainfall = Column(Float)
    temperature = Column(Float)
    crop = Column(String)
    yield_estimate = Column(String)
    profit = Column(String)

Base.metadata.create_all(bind=engine)

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

# ----------------------
# FastAPI Setup
# ----------------------
app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # restrict in production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ----------------------
# Pydantic Models
# ----------------------
class InputData(BaseModel):
    ph: float
    moisture: float
    rainfall: float
    temperature: float

class CropRecommendation(BaseModel):
    name: str
    yield_estimate: str
    profit: str

class RecommendationHistory(BaseModel):
    id: int
    ph: float
    moisture: float
    rainfall: float
    temperature: float
    crop: str
    yield_estimate: str
    profit: str

    class Config:
        orm_mode = True

# ----------------------
# API Endpoints
# ----------------------
@app.get("/")
def root():
    return {"message": "Crop Recommendation API with SQLite running"}

@app.post("/recommendations", response_model=List[CropRecommendation])
def recommend(data: InputData, db: Session = Depends(get_db)):
    # Dummy rules (replace with ML later)
    crops = []
    if 6.0 <= data.ph <= 7.5 and data.moisture > 20:
        crops.append({"name": "Rice", "yield_estimate": "3.2 t/ha", "profit": "₹25,000/ha"})
    if data.rainfall < 100 and data.ph >= 5.5:
        crops.append({"name": "Maize", "yield_estimate": "2.8 t/ha", "profit": "₹18,500/ha"})
    if data.moisture < 25 and data.temperature > 28:
        crops.append({"name": "Groundnut", "yield_estimate": "1.5 t/ha", "profit": "₹15,000/ha"})
    if not crops:
        crops.append({"name": "Millet", "yield_estimate": "1.2 t/ha", "profit": "₹10,000/ha"})

    # Save to DB
    for crop in crops:
        rec = RecommendationDB(
            ph=data.ph,
            moisture=data.moisture,
            rainfall=data.rainfall,
            temperature=data.temperature,
            crop=crop["name"],
            yield_estimate=crop["yield_estimate"],
            profit=crop["profit"],
        )
        db.add(rec)
    db.commit()

    return crops

@app.get("/history", response_model=List[RecommendationHistory])
def get_history(db: Session = Depends(get_db)):
    return db.query(RecommendationDB).all()
