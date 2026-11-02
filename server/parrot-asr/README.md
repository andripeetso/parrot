# parrot-asr

The LAN transcription server Parrot's `extras.server` points at. It runs on the omarchy PC: Parakeet TDT 0.6B v2 on the CPU, port 7886.

Install on the PC: copy `server.py` to `~/ai/parrot-asr/`, create `.venv` there with Python 3.12 and `pip install -r requirements.txt`, copy `parrot-asr.service` to `~/.config/systemd/user/`, then `systemctl --user enable --now parrot-asr`.

`Nice=-10` and `CPUWeight=1000` in the unit keep dictation fast while the PC builds or renders, because desktop apps there run at nice -8.
