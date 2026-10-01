"""Entry point. Run:  python main.py   (or launch the built .exe)."""
from app import config
from app.gui import main

if __name__ == "__main__":
    config.ensure_seed_data()   # seed data/ next to the exe on first run
    main()
