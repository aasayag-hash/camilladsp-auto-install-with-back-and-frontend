import sys
import json
import math
import time
import re
from datetime import datetime
from PySide6.QtWidgets import (QApplication, QMainWindow, QVBoxLayout, QHBoxLayout, 
                             QWidget, QLabel, QLineEdit, QPushButton, 
                             QStackedWidget, QTextEdit, QFrame, QRadioButton, QGroupBox,
                             QComboBox, QTableWidget, QTableWidgetItem, QHeaderView, 
                             QAbstractItemView, QCheckBox, QButtonGroup, QDialog,
                             QScrollArea, QTabWidget)
from PySide6.QtCore import Qt, QPointF, QRectF, QTimer
from PySide6.QtGui import QPainter, QPen, QColor, QPainterPath, QBrush, QLinearGradient, QFont

# Importacion CamillaDSP Segura
try:
    from camilladsp import CamillaClient as CamillaDSP
except:
    try:
        from camilladsp import CamillaConnection as CamillaDSP
    except:
        class CamillaDSP:
            def __init__(self, ip, port): pass
            def connect(self): pass

# --- DICCIONARIO DE IDIOMAS ---
LANG = {
    "es": {
        "title": "CAMILLADSP MASTER CONSOLE",
        "ip_label": "IP Servidor:",
        "port_label": "Puerto:",
        "btn_scan": "ESCANEAR HARDWARE",
        "btn_help": "AYUDA / MANUAL",
        "btn_lang": "EN / ES",
        "mode_title": "MODO DE TRABAJO",
        "rb_def": "DEFAULT (EQ existente)",
        "rb_in": "INPUT MODE (Multi-Select Pares Stereo)",
        "rb_out": "OUTPUT MODE (Multi-Select)",
        "btn_launch": "INICIAR ESTUDIO",
        "help_title": "Manual de Usuario - CamillaDSP",
        "help_text": """
=== CONTROLES DEL MOUSE (GRAFICO EQ) ===
- Doble Click (fondo): Crea un nuevo filtro EQ.
- Click Izquierdo sostenido: Arrastra y mueve el filtro (Frecuencia y Ganancia).
- Rueda del Mouse: Ajusta el ancho de banda (Factor Q).
- Click Derecho: Borra el filtro seleccionado.

=== VUMETROS Y COMPRESORES ===
- Etiquetas: Los nombres se importan automaticamente del hardware o mixer.
- Click Izquierdo en el Nombre del Canal (Salidas): Mutea (Rojo) o Activa (Verde) el canal.
- Doble Click en Vumetro de Salida: Crea un limitador/compresor fijando el Threshold.
- Click Derecho en Vumetro de Salida: Borra el compresor de ese canal.
- Boton AUTO (Tabla Compresores): Mide la dinamica por 5 seg y ajusta Atk/Rel.

=== FADERS DE VOLUMEN (MIXER) ===
- Modifican la ganancia directamente en el bloque Mixer de CamillaDSP.
- Click Izquierdo sostenido: Mueve el fader visualmente. El volumen real cambia al soltar el click para evitar microcortes de audio.
- Click Derecho: Resetea el fader a 0.0 dB instantaneamente.
- Boton +/- : Invierte la polaridad (fase) del canal de salida en el mixer.

=== TABLAS DE EDICION ===
Todas las celdas numericas (Freq, Gain, Q, Atk, Rel, etc.) se pueden editar manualmente haciendo doble click.
        """
    },
    "en": {
        "title": "CAMILLADSP MASTER CONSOLE",
        "ip_label": "Server IP:",
        "port_label": "Port:",
        "btn_scan": "SCAN HARDWARE",
        "btn_help": "HELP / MANUAL",
        "btn_lang": "ES / EN",
        "mode_title": "WORK MODE",
        "rb_def": "DEFAULT (Existing EQ)",
        "rb_in": "INPUT MODE (Multi-Select Stereo Pairs)",
        "rb_out": "OUTPUT MODE (Multi-Select)",
        "btn_launch": "LAUNCH STUDIO",
        "help_title": "User Manual - CamillaDSP",
        "help_text": """
=== MOUSE CONTROLS (EQ GRAPH) ===
- Double Click (background): Creates a new EQ filter.
- Left Click (hold): Drags and moves the filter (Frequency and Gain).
- Mouse Wheel: Adjusts the bandwidth (Q Factor).
- Right Click: Deletes the selected filter.

=== VU METERS & COMPRESSORS ===
- Labels: Channel names are auto-imported from hardware/mixer settings.
- Left Click on Channel Name (Outputs): Mutes (Red) or Unmutes (Green) the channel.
- Double Click on Output VU Meter: Creates a limiter/comp setting the Threshold.
- Right Click on Output VU Meter: Deletes the compressor for that channel.
- AUTO Button (Compressor Table): Measures dynamics for 5s and sets Atk/Rel.

=== VOLUME FADERS (MIXER) ===
- Adjusts gain directly inside the CamillaDSP Mixer block.
- Left Click (hold): Moves fader visually. The actual volume changes on release to prevent audio stuttering.
- Right Click: Resets fader to 0.0 dB instantly.
- +/- Button: Inverts the polarity (phase) of the output channel in the mixer.

=== EDITING TABLES ===
All numeric cells (Freq, Gain, Q, Atk, Rel, etc.) can be manually edited by double-clicking.
        """
    }
}

# --- MOTOR MATEMATICO EXACTO ---
def calcular_magnitud_biquad(params, freq_hz, sample_rate=44100):
    tipo = params.get("type", "")
    f0 = params.get("freq", 1000.0)
    gain = params.get("gain", 0.0)
    q = params.get("q", 1.0)
    if sample_rate <= 0: sample_rate = 44100
    if f0 <= 0: f0 = 10.0
    if q <= 0: q = 0.1
    w0 = 2.0 * math.pi * f0 / sample_rate
    cos_w0 = math.cos(w0); sin_w0 = math.sin(w0); alpha = sin_w0 / (2.0 * q)
    A = math.pow(10.0, gain / 40.0)
    b0=b1=b2=a0=a1=a2=0.0
    if tipo == "Peaking":
        b0 = 1.0 + alpha * A; b1 = -2.0 * cos_w0; b2 = 1.0 - alpha * A
        a0 = 1.0 + alpha / A; a1 = -2.0 * cos_w0; a2 = 1.0 - alpha / A
    elif tipo == "Lowpass":
        b0 = (1.0 - cos_w0) / 2.0; b1 = 1.0 - cos_w0; b2 = (1.0 - cos_w0) / 2.0
        a0 = 1.0 + alpha; a1 = -2.0 * cos_w0; a2 = 1.0 - alpha
    elif tipo == "Highpass":
        b0 = (1.0 + cos_w0) / 2.0; b1 = -(1.0 + cos_w0); b2 = (1.0 + cos_w0) / 2.0
        a0 = 1.0 + alpha; a1 = -2.0 * cos_w0; a2 = 1.0 - alpha
    elif tipo == "Highshelf":
        sqA = math.sqrt(A)
        b0 = A * ((A + 1.0) + (A - 1.0) * cos_w0 + 2.0 * sqA * alpha)
        b1 = -2.0 * A * ((A - 1.0) + (A + 1.0) * cos_w0)
        b2 = A * ((A + 1.0) + (A - 1.0) * cos_w0 - 2.0 * sqA * alpha)
        a0 = (A + 1.0) - (A - 1.0) * cos_w0 + 2.0 * sqA * alpha
        a1 = 2.0 * ((A - 1.0) - (A + 1.0) * cos_w0)
        a2 = (A + 1.0) - (A - 1.0) * cos_w0 - 2.0 * sqA * alpha
    elif tipo == "Lowshelf":
        sqA = math.sqrt(A)
        b0 = A * ((A + 1.0) - (A - 1.0) * cos_w0 + 2.0 * sqA * alpha)
        b1 = 2.0 * A * ((A - 1.0) - (A + 1.0) * cos_w0)
        b2 = A * ((A + 1.0) - (A - 1.0) * cos_w0 - 2.0 * sqA * alpha)
        a0 = (A + 1.0) + (A - 1.0) * cos_w0 + 2.0 * sqA * alpha
        a1 = -2.0 * ((A - 1.0) + (A + 1.0) * cos_w0)
        a2 = (A + 1.0) + (A - 1.0) * cos_w0 - 2.0 * sqA * alpha
    else: return 0.0

    w = 2.0 * math.pi * freq_hz / sample_rate
    z1_r, z1_i = math.cos(-w), math.sin(-w); z2_r, z2_i = math.cos(-2.0*w), math.sin(-2.0*w)
    n_r = b0 + b1 * z1_r + b2 * z2_r; n_i = b1 * z1_i + b2 * z2_i
    d_r = a0 + a1 * z1_r + a2 * z2_r; d_i = a1 * z1_i + a2 * z2_i
    mag_num = math.hypot(n_r, n_i); mag_den = math.hypot(d_r, d_i)
    if mag_den == 0.0 or mag_num == 0.0: return -100.0
    return 20.0 * math.log10(mag_num / mag_den)

# --- VUMETRO PRO ---
class ProVUMeter(QWidget):
    def __init__(self, name="CH"):
        super().__init__(); self.setMinimumWidth(60); self.level = -80.0; self.peak = -80.0; self.peak_timer = 0; self.name = name
        self.comp_threshold = None
        self.is_muted = False
    def set_level(self, db):
        self.level = db if db is not None else -80.0
        if self.level > self.peak: self.peak = self.level; self.peak_timer = 40
        elif self.peak_timer > 0: self.peak_timer -= 1
        else: self.peak -= 0.5
        self.update()
    def paintEvent(self, event):
        p = QPainter(self); p.setRenderHint(QPainter.Antialiasing); w, h = self.width(), self.height()
        p.fillRect(0, 0, w, h, QColor(10, 10, 10)); fh = 45; bh = h - fh; bx = 18; bw = 22
        p.fillRect(bx, 0, bw, bh, QColor(35, 35, 35))
        p.setPen(Qt.white); p.setFont(QFont("Arial", 7))
        for db in [0, -6, -12, -24, -40, -60, -80]:
            y = bh - ((db + 80) / 80 * bh)
            p.drawLine(bx + bw, int(y), bx + bw + 5, int(y)); p.drawText(bx + bw + 8, int(y) + 3, str(db))
        lh = (max(-80, self.level) + 80) / 80 * bh
        grad = QLinearGradient(0, bh, 0, 0); grad.setColorAt(0, Qt.green); grad.setColorAt(0.7, Qt.yellow); grad.setColorAt(0.9, Qt.red)
        p.fillRect(QRectF(bx, bh - lh, bw, lh), grad)
        
        if getattr(self, 'is_output', False) and self.comp_threshold is not None:
            th_y = bh - ((self.comp_threshold + 80) / 80 * bh)
            p.fillRect(QRectF(bx, 0, bw, th_y), QColor(255, 0, 0, 90))
            p.setPen(QPen(Qt.red, 2)); p.drawLine(bx, int(th_y), bx+bw, int(th_y))

        py = bh - ((max(-80, self.peak) + 80) / 80 * bh); p.setPen(QPen(Qt.white, 2.5)); p.drawLine(bx-3, int(py), bx+bw+3, int(py))
        
        p.setFont(QFont("Arial", 8, QFont.Bold))
        text_rect = QRectF(0, bh + 5, w, 40)
        if getattr(self, 'is_output', False):
            if self.is_muted:
                p.setPen(Qt.red)
                p.drawText(text_rect, Qt.AlignCenter, f"{self.name}\n[MUTE]")
            else:
                p.setPen(Qt.green)
                p.drawText(text_rect, Qt.AlignCenter, f"{self.name}\n(active)")
        else:
            p.setPen(Qt.white)
            p.drawText(text_rect, Qt.AlignCenter, self.name)

    def mouseDoubleClickEvent(self, event):
        if getattr(self, 'is_output', False) and hasattr(self, 'app_ref'):
            bh = self.height() - 45; y = event.position().y()
            if y <= bh:
                db = max(-80.0, min(0.0, -80 * (y / bh)))
                self.app_ref.crear_compresor(self.name, self.ch_index, db, self)

    def mousePressEvent(self, event):
        if not getattr(self, 'is_output', False) or not hasattr(self, 'app_ref'): return
        bh = self.height() - 45
        if event.position().y() > bh and event.button() == Qt.LeftButton:
            self.is_muted = not self.is_muted
            self.app_ref.toggle_mute(self.ch_index, self.is_muted, self)
            self.update()
        elif event.button() == Qt.RightButton:
            self.app_ref.borrar_compresor_por_id(f"Comp_{self.app_ref.clean_name(self.name)}")

# --- FADER PRO ---
class ProFader(QWidget):
    def __init__(self, name="VOL", ch_index=0, init_db=0.0):
        super().__init__(); self.setMinimumWidth(40); self.name = name; self.ch_index = ch_index
        self.db = init_db; self.app_ref = None; self.is_dragging = False

    def db_to_y(self, db, h):
        db = max(-80.0, min(12.0, db))
        if db >= 0: return (12.0 - db) / 12.0 * (0.2 * h)
        else: return 0.2 * h + (-db / 80.0) * (0.8 * h)

    def y_to_db(self, y, h):
        if y <= 0.2 * h: db = 12.0 - (y / (0.2 * h)) * 12.0
        else: db = - ((y - 0.2 * h) / (0.8 * h)) * 80.0
        return max(-80.0, min(12.0, db))

    def paintEvent(self, event):
        p = QPainter(self); p.setRenderHint(QPainter.Antialiasing); w, h = self.width(), self.height()
        p.fillRect(0, 0, w, h, QColor(10, 10, 10)); fh = 45; bh = h - fh; tx = w // 2 - 2
        p.fillRect(tx, 0, 4, bh, QColor(20, 20, 20))
        p.setPen(QColor(100, 100, 100))
        for db in [12, 0, -12, -24, -40, -60, -80]:
            y = self.db_to_y(db, bh)
            p.drawLine(tx - 6, int(y), tx + 10, int(y))
            if db == 0: p.setPen(Qt.green); p.drawLine(tx - 8, int(y), tx + 12, int(y)); p.setPen(QColor(100, 100, 100))
        fy = self.db_to_y(self.db, bh)
        p.setBrush(QColor(0, 150, 255) if self.is_dragging else QColor(150, 150, 150)); p.setPen(Qt.NoPen)
        p.drawRoundedRect(tx - 12, int(fy) - 6, 28, 12, 3, 3)
        p.setPen(Qt.white); p.drawLine(tx - 10, int(fy), tx + 10, int(fy))
        p.setFont(QFont("Arial", 7)); p.drawText(QRectF(0, bh + 5, w, 15), Qt.AlignCenter, f"{self.db:.1f}")
        p.setFont(QFont("Arial", 8, QFont.Bold)); p.drawText(QRectF(0, bh + 20, w, 20), Qt.AlignCenter, "VOL")

    def mousePressEvent(self, event):
        if event.button() == Qt.LeftButton:
            self.is_dragging = True; self.update_db_from_mouse(event.position().y())
        elif event.button() == Qt.RightButton:
            self.db = 0.0; self.enviar_gain(); self.update()

    def mouseMoveEvent(self, event):
        if self.is_dragging: self.update_db_from_mouse(event.position().y())

    def mouseReleaseEvent(self, event):
        if event.button() == Qt.LeftButton:
            self.is_dragging = False; self.enviar_gain(); self.update()
            if self.app_ref: self.app_ref.guardar_config()

    def update_db_from_mouse(self, y):
        bh = self.height() - 45; self.db = self.y_to_db(y, bh); self.update()

    def enviar_gain(self):
        if not self.app_ref: return
        mixer_name = None
        for step in self.app_ref.config_raw.get("pipeline", []):
            if step.get("type") == "Mixer":
                mixer_name = step.get("name"); break
        if mixer_name and "mixers" in self.app_ref.config_raw and mixer_name in self.app_ref.config_raw["mixers"]:
            m_conf = self.app_ref.config_raw["mixers"][mixer_name]
            for mapping in m_conf.get("mapping", []):
                if mapping.get("dest") == self.ch_index:
                    for src in mapping.get("sources", []): src["gain"] = float(f"{self.db:.1f}")
            try: self.app_ref.cdsp.query("PatchConfig", {"mixers": {mixer_name: m_conf}})
            except Exception as e: pass 

# --- GRAFICO PRO ---
class EQGraph(QFrame):
    def __init__(self, parent_app):
        super().__init__(); self.app = parent_app; self.setMinimumHeight(250); self.setMouseTracking(True)
        self.setFocusPolicy(Qt.StrongFocus); self.filters = {}; self.active_drag = None; self.hovered_point = None
        self.sample_rate = 44100
    def set_filters(self, d): self.filters = d; self.update()
    def x_to_f(self, x): return math.pow(10, math.log10(20) + (x / self.width()) * (math.log10(20000) - math.log10(20)))
    def f_to_x(self, f): return self.width() * (math.log10(max(20, min(20000, f))) - math.log10(20)) / (math.log10(20000) - math.log10(20))
    def db_to_y(self, db): return self.height() * (12 - max(-12, min(12, db))) / 24
    def y_to_db(self, y): return 12 - (y / self.height()) * 24

    def paintEvent(self, event):
        p = QPainter(self); p.setRenderHint(QPainter.Antialiasing); w, h = self.width(), self.height()
        p.fillRect(0, 0, w, h, Qt.black)
        for decade in [10, 100, 1000, 10000]:
            for i in range(1, 10):
                f = decade * i
                if f < 20 or f > 20000: continue
                x = self.f_to_x(f); alpha = 130 if i == 1 else 35
                p.setPen(QPen(QColor(255, 255, 255, alpha), 1)); p.drawLine(int(x), 0, int(x), h)
                if i in [1, 2, 5]:
                    p.setPen(Qt.white); p.setFont(QFont("Arial", 8)); p.drawText(int(x) + 3, h - 10, f"{int(f) if f < 1000 else str(int(f/1000)) + 'k'}")
        for db in range(-12, 13):
            y = self.db_to_y(db); alpha = 180 if db == 0 else 70 if db % 3 == 0 else 25
            p.setPen(QPen(QColor(255, 255, 255, alpha), 1)); p.drawLine(0, int(y), w, int(y))
            if db % 3 == 0: p.setPen(Qt.white); p.drawText(8, int(y) - 5, f"{db}dB")
        path = QPainterPath(); target = self.active_drag or self.hovered_point
        for i in range(w + 1):
            f = self.x_to_f(i)
            total = sum(calcular_magnitud_biquad(fd["parameters"], f, self.sample_rate) for fd in self.filters.values())
            y = self.db_to_y(total)
            if i == 0: path.moveTo(i, y)
            else: path.lineTo(i, y)
        p.setPen(QPen(QColor(0, 255, 150), 3.5)); p.drawPath(path)
        
        for i, (name, data) in enumerate(self.filters.items()):
            pr = data["parameters"]; x, y = self.f_to_x(pr["freq"]), self.db_to_y(pr.get("gain", 0))
            sel = (name == target); p.setBrush(QBrush(Qt.white if sel else QColor(0, 150, 255))); p.drawEllipse(QPointF(x, y), 8, 8)
            p.setPen(Qt.white); p.setFont(QFont("Arial", 10, QFont.Bold))
            p.drawText(QRectF(x - 10, y - 28, 20, 20), Qt.AlignCenter, str(i + 1))
            
            if sel:
                txt = f"F:{pr['freq']:.0f}Hz | G:{pr.get('gain',0):.1f}dB | Q:{pr.get('q',1.0):.2f}"
                p.setBrush(QBrush(QColor(0,0,0,235))); p.setPen(QPen(Qt.cyan, 1.5))
                
                bw, bh = 130, 60
                bx = int(x) - (bw // 2)
                by = int(y) - bh - 20 
                
                if by < 0: by = int(y) + 20 
                if by + bh > h: by = h - bh
                if bx < 0: bx = 0
                if bx + bw > w: bx = w - bw
                
                p.drawRoundedRect(bx, by, bw, bh, 7, 7)
                p.setPen(Qt.white); p.setFont(QFont("Arial", 8))
                p.drawText(QRectF(bx, by, bw, bh), Qt.AlignCenter, txt)

    def mouseDoubleClickEvent(self, event): 
        self.app.crear_filtro_en_posicion(self.x_to_f(event.position().x()), self.y_to_db(event.position().y()))
        
    def mousePressEvent(self, event):
        self.setFocus()
        for name, data in self.filters.items():
            p = data["parameters"]; fx, fy = self.f_to_x(p["freq"]), self.db_to_y(p.get("gain", 0))
            if math.hypot(event.position().x()-fx, event.position().y()-fy) < 20: 
                if event.button() == Qt.RightButton:
                    self.app.borrar(name); self.hovered_point = None; self.active_drag = None
                elif event.button() == Qt.LeftButton:
                    self.active_drag = name; self.app.marcar_fila_activa(name)
                return
                
    def mouseMoveEvent(self, event):
        if self.active_drag and (event.buttons() & Qt.LeftButton):
            p = self.filters[self.active_drag]["parameters"]
            p["freq"] = float(self.x_to_f(event.position().x()))
            self.app.actualizar_celda(self.active_drag, 2, f"{p['freq']:.0f}")
            if "gain" in p: 
                p["gain"] = float(self.y_to_db(event.position().y()))
                self.app.actualizar_celda(self.active_drag, 3, f"{p['gain']:.1f}")
            self.app.enviar_parche(self.active_drag, p); self.app.marcar_fila_activa(self.active_drag); self.update()
        else:
            old = self.hovered_point; self.hovered_point = None
            for name, data in self.filters.items():
                p = data["parameters"]; fx, fy = self.f_to_x(p["freq"]), self.db_to_y(p.get("gain", 0))
                if math.hypot(event.position().x()-fx, event.position().y()-fy) < 20: 
                    self.hovered_point = name; break
            if old != self.hovered_point: self.update()
            
    def wheelEvent(self, event):
        self.setFocus()
        target = self.active_drag or self.hovered_point
        if not target:
            for name, data in self.filters.items():
                p = data["parameters"]; fx, fy = self.f_to_x(p["freq"]), self.db_to_y(p.get("gain", 0))
                if math.hypot(event.position().x()-fx, event.position().y()-fy) < 20: 
                    target = name; break
        if target and target in self.filters:
            p = self.filters[target]["parameters"]
            step = 0.1 if event.angleDelta().y() > 0 else -0.1
            p["q"] = max(0.1, min(20, p.get("q", 1.0) + step))
            self.app.enviar_parche(target, p); self.app.actualizar_celda(target, 4, f"{p['q']:.2f}"); self.update(); event.accept()
            
    def mouseReleaseEvent(self, event): 
        if event.button() == Qt.LeftButton and self.active_drag:
            self.active_drag = None; self.app.actualizar_tabla_ui()

# --- MANUAL DIALOG ---
class HelpDialog(QDialog):
    def __init__(self, lang="es", parent=None):
        super().__init__(parent); self.setWindowTitle(LANG[lang]["help_title"]); self.resize(700, 450)
        self.setStyleSheet("background: #121212; color: white;")
        layout = QVBoxLayout(self)
        txt = QTextEdit(); txt.setReadOnly(True); txt.setStyleSheet("background: #1a1a1a; font-family: Consolas; font-size: 14px; border: 1px solid #444;")
        txt.setText(LANG[lang]["help_text"]); layout.addWidget(txt)
        btn = QPushButton("OK"); btn.setStyleSheet("background: #007bff; font-weight: bold; height: 35px; border-radius: 5px;")
        btn.clicked.connect(self.accept); layout.addWidget(btn)

# --- APP ---
class PEQApp(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("CamillaDSP Pro Master - Dual Control")
        self.setMinimumSize(1024, 600)
        self.resize(1250, 680)
        self.setStyleSheet("QMainWindow { background: #050505; } QLabel { color: #fff; }")
        c = QWidget(); self.layout = QVBoxLayout(c); self.setCentralWidget(c); self.stack = QStackedWidget(); self.layout.addWidget(self.stack)
        self.log_v = QTextEdit(); self.log_v.setReadOnly(True); self.log_v.setMaximumHeight(65); self.log_v.setStyleSheet("background:#000; color:#0f0; border:1px solid #333; font-family:Consolas;")
        self.layout.addWidget(self.log_v); self.filtros_biquad = {}; self.config_raw = {}; self.v_in = []; self.v_out = []
        self.mode = "Default"; self.sel_items = []; self.sample_rate = 44100; self.auto_samplers = {}; self.current_lang = "es"
        self.init_login()

    def clean_name(self, n): return re.sub(r'[^a-zA-Z0-9]', '', str(n))

    def log_debug(self, msg):
        """Registra mensajes con timestamp en la consola"""
        ts = datetime.now().strftime("%H:%M:%S.%f")[:-3]
        self.log_v.append(f"[{ts}] {msg}")

    def init_login(self):
        self.p_login = QWidget(); l_main = QVBoxLayout(self.p_login); card = QFrame(); card.setFixedWidth(620); card.setObjectName("MainCard")
        
        card.setStyleSheet("""
            #MainCard { background: #121212; border-radius: 15px; border: 2px solid #00ffff; } 
            #ChoicesFrame { background-color: #050505; }
            QLineEdit { height: 30px; background: #1a1a1a; color: white; border: 1px solid #444; padding: 5px; } 
            QPushButton { height: 40px; background: #007bff; color: white; font-weight: bold; border-radius: 8px; } 
            QRadioButton, QCheckBox { color: #fff; padding: 2px; min-height: 24px; font-size: 13px; background: transparent; } 
            QRadioButton:checked, QCheckBox:checked { color: #00ffff; font-weight: bold; background: #222; border-radius: 5px; }
            QRadioButton::indicator { width: 16px; height: 16px; border: 1px solid #555; border-radius: 8px; background: #111; }
            QCheckBox::indicator { width: 16px; height: 16px; border: 1px solid #555; border-radius: 4px; background: #111; }
            QRadioButton::indicator:checked, QCheckBox::indicator:checked { background-color: #00ffff; border: 2px solid white; }
        """)
        
        l_card = QVBoxLayout(card); l_card.setContentsMargins(20, 20, 20, 20); l_card.setSpacing(10)
        
        h_top = QHBoxLayout()
        self.btn_lang = QPushButton(LANG[self.current_lang]["btn_lang"])
        self.btn_lang.setFixedWidth(80); self.btn_lang.setStyleSheet("background: #555;"); self.btn_lang.clicked.connect(self.toggle_lang)
        self.btn_help = QPushButton(LANG[self.current_lang]["btn_help"])
        self.btn_help.setStyleSheet("background: #28a745;"); self.btn_help.clicked.connect(self.show_help)
        h_top.addWidget(self.btn_lang); h_top.addStretch(); h_top.addWidget(self.btn_help); l_card.addLayout(h_top)

        self.lbl_title = QLabel(LANG[self.current_lang]["title"])
        self.lbl_title.setAlignment(Qt.AlignCenter); self.lbl_title.setStyleSheet("font-size: 22px; color:#00ffff; border:none;")
        l_card.addWidget(self.lbl_title)
        
        # --- CARGAR CONFIGURACIÓN GUARDADA ---
        saved_ip = "127.0.0.1"
        saved_port = "1234"
        try:
            with open("app_settings.json", "r") as f:
                settings = json.load(f)
                saved_ip = settings.get("ip", "127.0.0.1")
                saved_port = str(settings.get("port", "1234"))
        except:
            pass # Si no existe o hay error, mantenemos los valores por defecto
        # -------------------------------------

        h_ip_port = QHBoxLayout()
        v_ip = QVBoxLayout()
        self.lbl_ip = QLabel(LANG[self.current_lang]["ip_label"]); v_ip.addWidget(self.lbl_ip)
        self.ip_i = QLineEdit(saved_ip); v_ip.addWidget(self.ip_i)
        
        v_port = QVBoxLayout()
        self.lbl_port = QLabel(LANG[self.current_lang]["port_label"]); v_port.addWidget(self.lbl_port)
        self.port_i = QLineEdit(saved_port); self.port_i.setFixedWidth(100); v_port.addWidget(self.port_i)
        
        h_ip_port.addLayout(v_ip); h_ip_port.addLayout(v_port); l_card.addLayout(h_ip_port)
        
        self.btn_s = QPushButton(LANG[self.current_lang]["btn_scan"]); self.btn_s.clicked.connect(self.scan); l_card.addWidget(self.btn_s)
        
        self.g_mode = QGroupBox(LANG[self.current_lang]["mode_title"]); self.g_mode.hide(); gl = QVBoxLayout(self.g_mode)
        self.rb_d = QRadioButton(LANG[self.current_lang]["rb_def"]); self.rb_d.setChecked(True)
        self.rb_i = QRadioButton(LANG[self.current_lang]["rb_in"]); self.rb_o = QRadioButton(LANG[self.current_lang]["rb_out"])
        gl.addWidget(self.rb_d); gl.addWidget(self.rb_i); gl.addWidget(self.rb_o)

        self.scroll_area = QScrollArea()
        self.scroll_area.setWidgetResizable(True)
        self.scroll_area.setMinimumHeight(200)
        self.scroll_area.setMaximumHeight(350)
        self.scroll_area.setStyleSheet("""
            QScrollArea { border: 1px solid #333; background-color: #050505; border-radius: 5px; } 
            QScrollBar:vertical { background: #111; width: 14px; } 
            QScrollBar::handle:vertical { background: #444; border-radius: 7px; min-height: 20px; }
        """)
        
        self.c_frame = QFrame()
        self.c_frame.setObjectName("ChoicesFrame")
        self.c_lay = QVBoxLayout(self.c_frame)
        self.c_lay.setSpacing(2)
        
        self.scroll_area.setWidget(self.c_frame)
        gl.addWidget(self.scroll_area)

        self.btn_go = QPushButton(LANG[self.current_lang]["btn_launch"]); self.btn_go.clicked.connect(self.start); self.btn_go.hide()
        l_card.addWidget(self.g_mode); l_card.addWidget(self.btn_go)
        l_main.addStretch(); hc = QHBoxLayout(); hc.addStretch(); hc.addWidget(card); hc.addStretch(); l_main.addLayout(hc); l_main.addStretch()
        self.stack.addWidget(self.p_login); self.rb_i.toggled.connect(self.list_choices); self.rb_o.toggled.connect(self.list_choices); self.rb_d.toggled.connect(self.list_choices)

    def toggle_lang(self):
        self.current_lang = "en" if self.current_lang == "es" else "es"; d = LANG[self.current_lang]
        self.btn_lang.setText(d["btn_lang"]); self.btn_help.setText(d["btn_help"]); self.lbl_title.setText(d["title"])
        self.lbl_ip.setText(d["ip_label"]); self.lbl_port.setText(d["port_label"])
        self.btn_s.setText(d["btn_scan"]); self.g_mode.setTitle(d["mode_title"])
        self.rb_d.setText(d["rb_def"]); self.rb_i.setText(d["rb_in"]); self.rb_o.setText(d["rb_out"]); self.btn_go.setText(d["btn_launch"])
        
        if hasattr(self, 'tabs'):
            self.tabs.setTabText(0, "VÚMETROS Y DINÁMICA" if self.current_lang == "es" else "VUMETERS & DYNAMICS")
            self.tabs.setTabText(1, "FILTROS Y EQ" if self.current_lang == "es" else "EQ & FILTERS")

    def show_help(self): diag = HelpDialog(self.current_lang, self); diag.exec()

    def scan(self):
        ip = self.ip_i.text().strip()
        try: port = int(self.port_i.text().strip())
        except ValueError: self.log_v.append("Error: El puerto debe ser un número entero."); return

        # --- GUARDAR CONFIGURACIÓN AL CONECTAR ---
        try:
            with open("app_settings.json", "w") as f:
                json.dump({"ip": ip, "port": port}, f)
        except Exception as e:
            self.log_v.append(f"No se pudo guardar la configuración: {e}")
        # -----------------------------------------

        self.cdsp = CamillaDSP(ip, port)
        try:
            self.cdsp.connect(); c = self.cdsp.query("GetConfigJson"); self.config_raw = json.loads(c) if isinstance(c, str) else c
            self.sample_rate = self.config_raw.get("devices", {}).get("samplerate", 44100)
            self.log_debug(f"✓ Conectado a {ip}:{port}. Sample Rate: {self.sample_rate} Hz")
            self.g_mode.show(); self.btn_go.show(); self.btn_s.hide()
        except Exception as e: self.log_debug(f"✗ Error al conectar con {ip}:{port} -> {e}")

    def get_labels(self, target):
        num_channels = 0
        lbls = []
        
        if target == "playback":
            mixer_name = None
            for step in self.config_raw.get("pipeline", []):
                if step.get("type") == "Mixer":
                    mixer_name = step.get("name"); break
            if mixer_name and "mixers" in self.config_raw and mixer_name in self.config_raw["mixers"]:
                m_conf = self.config_raw["mixers"][mixer_name]
                num_channels = m_conf.get("channels", {}).get("out", 0)
                lbls = m_conf.get("labels", [])
                
        if num_channels == 0:
            dev = self.config_raw.get("devices", {}).get(target, {})
            num_channels = dev.get("channels", 2)
            lbls = dev.get("labels", [])
            
        pref = "IN" if target == "capture" else "OUT"
        final_labels = []
        for i in range(num_channels):
            if i < len(lbls) and lbls[i]:
                final_labels.append(lbls[i])
            else:
                final_labels.append(f"{pref}{i}")
                
        return final_labels

    def list_choices(self):
        for i in reversed(range(self.c_lay.count())): 
            w = self.c_lay.itemAt(i).widget()
            if w: w.setParent(None)
        if self.rb_d.isChecked(): return
        
        if self.rb_i.isChecked():
            l = self.get_labels("capture")
            for i in range(0, len(l), 2):
                n1, n2 = l[i], l[i+1] if i+1 < len(l) else "N/A"
                cb = QCheckBox(f"Par Stereo: {n1} & {n2}")
                cb.setProperty("data", (i, i+1, n1, n2, "in"))
                self.c_lay.addWidget(cb)
                
        elif self.rb_o.isChecked():
            l = self.get_labels("playback")
            for i in range(len(l)):
                cb = QCheckBox(f"Output Channel: {l[i]}"); cb.setProperty("data", (i, l[i])); self.c_lay.addWidget(cb)

    def start(self):
        self.mode = "Input" if self.rb_i.isChecked() else "Output" if self.rb_o.isChecked() else "Default"
        self.sel_items = []
        
        if self.mode in ["Input", "Output"]:
            for cb in self.c_frame.findChildren(QCheckBox):
                if cb.isChecked(): self.sel_items.append(cb.property("data"))
                
        if self.mode != "Default" and not self.sel_items:
            self.log_v.append("ERROR: Selecciona al menos un canal o par."); return

        all_f = self.config_raw.get("filters", {})
        if self.mode == "Default": self.filtros_biquad = {k:v for k,v in all_f.items() if v.get("type")=="Biquad"}
        else:
            pref = "EQin_" if self.mode == "Input" else "EQout_"
            self.filtros_biquad = {k:v for k,v in all_f.items() if k.startswith(pref) and v.get("type")=="Biquad"}
        
        self.init_studio(); self.stack.setCurrentIndex(1); self.t = QTimer(); self.t.timeout.connect(self.up_v); self.t.start(50)

    def init_studio(self):
        p = QWidget()
        main_lay = QVBoxLayout(p)
        main_lay.setContentsMargins(5, 5, 5, 5)
        
        self.tabs = QTabWidget()
        self.tabs.setStyleSheet("""
            QTabWidget::pane { border: 1px solid #333; background: #050505; }
            QTabBar::tab { background: #222; color: #ccc; padding: 10px 20px; border: 1px solid #333; border-bottom: none; border-top-left-radius: 4px; border-top-right-radius: 4px; font-weight: bold;}
            QTabBar::tab:selected { background: #007bff; color: white; border-top: 2px solid #00ffff; }
        """)
        
        tab_vu = QWidget()
        tab_vu.setObjectName("TabVU")
        tab_vu.setStyleSheet("#TabVU { background-color: #050505; }")
        lay_vu = QVBoxLayout(tab_vu)
        
        scroll_vu = QScrollArea()
        scroll_vu.setWidgetResizable(True)
        scroll_vu.setStyleSheet("""
            QScrollArea { border: none; background-color: #050505; }
            QScrollArea > QWidget > QWidget { background-color: #050505; }
            QScrollBar:horizontal { background: #111; height: 14px; }
            QScrollBar::handle:horizontal { background: #444; border-radius: 7px; min-width: 20px; }
        """)
        scroll_vu.viewport().setStyleSheet("background-color: #050505;")
        
        vu_container = QWidget()
        vu_container.setObjectName("VuCont")
        vu_container.setStyleSheet("#VuCont { background-color: #050505; }")
        vu_layout = QHBoxLayout(vu_container)
        vu_layout.setAlignment(Qt.AlignLeft) 
        
        dev = self.config_raw["devices"]
        li, lo = self.get_labels("capture"), self.get_labels("playback")
        self.v_in = []; self.v_out = []
        
        for n in li: 
            vu = ProVUMeter(n); vu_layout.addWidget(vu); self.v_in.append(vu)
            
        if li and lo:
            sep = QFrame(); sep.setFrameShape(QFrame.VLine); sep.setStyleSheet("color: #444;")
            vu_layout.addWidget(sep)
            
        mixer_name = None
        for step in self.config_raw.get("pipeline", []):
            if step.get("type") == "Mixer":
                mixer_name = step.get("name"); break

        for i, n in enumerate(lo): 
            strip = QWidget(); slay = QHBoxLayout(strip); slay.setContentsMargins(0,0,0,0)
            
            vu = ProVUMeter(n)
            vu.is_output = True; vu.ch_index = i; vu.app_ref = self
            comp_name = f"Comp_{self.clean_name(n)}"
            if "processors" in self.config_raw and comp_name in self.config_raw["processors"]:
                vu.comp_threshold = self.config_raw["processors"][comp_name]["parameters"].get("threshold")
            self.v_out.append(vu)
            
            init_db = 0.0
            init_inv = False
            init_mute = False
            if mixer_name and "mixers" in self.config_raw and mixer_name in self.config_raw["mixers"]:
                m_conf = self.config_raw["mixers"][mixer_name]
                for mapping in m_conf.get("mapping", []):
                    if mapping.get("dest") == i:
                        init_mute = mapping.get("mute", False)
                        srcs = mapping.get("sources", [])
                        if srcs: 
                            init_db = srcs[0].get("gain", 0.0)
                            init_inv = srcs[0].get("inverted", False)
                        break

            vu.is_muted = init_mute
            fader_col = QWidget(); flay = QVBoxLayout(fader_col); flay.setContentsMargins(0,0,0,0); flay.setSpacing(5)
            fader = ProFader(n, i, init_db); fader.app_ref = self
            flay.addWidget(fader, 1)
            
            btn_pol = QPushButton("+/-")
            btn_pol.setCheckable(True); btn_pol.setChecked(init_inv); btn_pol.setFixedSize(40, 22)
            btn_pol.setStyleSheet("QPushButton { background: #333; color: white; border-radius: 3px; font-weight: bold; } QPushButton:checked { background: #d9534f; color: white; }")
            btn_pol.clicked.connect(lambda checked, ch=i: self.toggle_polarity(ch, checked))
            flay.addWidget(btn_pol, 0, Qt.AlignHCenter)

            slay.addWidget(vu); slay.addWidget(fader_col); vu_layout.addWidget(strip)
            
        scroll_vu.setWidget(vu_container)
        lay_vu.addWidget(scroll_vu, 1) 
        
        self.comp_table = QTableWidget(0, 9); self.comp_table.setHorizontalHeaderLabels(["Comp ID", "Atk", "Rel", "Thrsh", "Ratio", "Makeup", "Clip", "Auto", "Del"])
        self.comp_table.horizontalHeader().setSectionResizeMode(QHeaderView.Stretch); self.comp_table.setSelectionBehavior(QAbstractItemView.SelectRows)
        self.comp_table.verticalHeader().setDefaultSectionSize(35)
        lay_vu.addWidget(self.comp_table, 0) 

        tab_eq = QWidget()
        tab_eq.setObjectName("TabEQ")
        tab_eq.setStyleSheet("#TabEQ { background-color: #050505; }")
        lay_eq = QVBoxLayout(tab_eq)
        
        self.graph = EQGraph(self); self.graph.sample_rate = self.sample_rate; self.graph.set_filters(self.filtros_biquad)
        lay_eq.addWidget(self.graph, 1) 
        
        self.table = QTableWidget(0, 6); self.table.setHorizontalHeaderLabels(["Filter ID", "Type", "Freq", "Gain", "Q", "Del"])
        self.table.horizontalHeader().setSectionResizeMode(QHeaderView.Stretch); self.table.setSelectionBehavior(QAbstractItemView.SelectRows)
        self.table.verticalHeader().setDefaultSectionSize(35)
        lay_eq.addWidget(self.table, 0) 
        
        t_style = """
            QTableWidget { background: #111; color: white; border: none; gridline-color: #333; selection-background-color: #0055ff; selection-color: white; font-family: Consolas; font-size: 13px; }
            QHeaderView::section { background: #1a1a1a; color: #00ffff; font-weight: bold; border: 1px solid #333; height: 35px; }
            QComboBox { background: #333; color: white; border: 1px solid #555; border-radius: 3px; padding: 2px; }
            QComboBox QAbstractItemView { background-color: #222; color: white; selection-background: #007bff; }
            QPushButton { background: #400; color: #f55; border: 1px solid #600; border-radius: 3px; font-weight: bold; }
        """
        self.table.setStyleSheet(t_style); self.comp_table.setStyleSheet(t_style)
        self.table.itemChanged.connect(self.modificar_filtro_desde_tabla)
        self.comp_table.itemChanged.connect(self.modificar_compresor_desde_tabla)

        title_vu = "VÚMETROS Y DINÁMICA" if self.current_lang == "es" else "VUMETERS & DYNAMICS"
        title_eq = "FILTROS Y EQ" if self.current_lang == "es" else "EQ & FILTERS"
        self.tabs.addTab(tab_vu, title_vu)
        self.tabs.addTab(tab_eq, title_eq)
        
        main_lay.addWidget(self.tabs)
        self.actualizar_tabla_ui(); self.actualizar_tabla_comp_ui(); self.stack.addWidget(p)

    def toggle_polarity(self, ch_index, is_inverted):
        mixer_name = None
        for step in self.config_raw.get("pipeline", []):
            if step.get("type") == "Mixer":
                mixer_name = step.get("name"); break
        if mixer_name and "mixers" in self.config_raw and mixer_name in self.config_raw["mixers"]:
            m_conf = self.config_raw["mixers"][mixer_name]
            for mapping in m_conf.get("mapping", []):
                if mapping.get("dest") == ch_index:
                    for src in mapping.get("sources", []): src["inverted"] = is_inverted
            try:
                self.log_debug(f"➤ PatchConfig Polarity: CH {ch_index} = {'INVERTIDA' if is_inverted else 'NORMAL'}")
                self.cdsp.query("PatchConfig", {"mixers": {mixer_name: m_conf}})
                self.guardar_config()
                self.log_debug(f"✓ Polaridad CH {ch_index}: {'INVERTIDA' if is_inverted else 'NORMAL'}")
            except Exception as e: 
                self.log_debug(f"✗ Error polarity: {e}")

    def toggle_mute(self, ch_index, is_muted, vu_ref):
        mixer_name = None
        for step in self.config_raw.get("pipeline", []):
            if step.get("type") == "Mixer":
                mixer_name = step.get("name"); break
        if mixer_name and "mixers" in self.config_raw and mixer_name in self.config_raw["mixers"]:
            m_conf = self.config_raw["mixers"][mixer_name]
            for mapping in m_conf.get("mapping", []):
                if mapping.get("dest") == ch_index: mapping["mute"] = is_muted
            try:
                self.log_debug(f"➤ PatchConfig Mute: CH {ch_index} = {'MUTEADO' if is_muted else 'ACTIVO'}")
                self.cdsp.query("PatchConfig", {"mixers": {mixer_name: m_conf}})
                self.guardar_config()
                self.log_debug(f"✓ Canal OUT {ch_index}: {'MUTEADO' if is_muted else 'ACTIVO'}")
            except Exception as e:
                self.log_debug(f"✗ Error mute: {e}")

    def guardar_config(self):
        try:
            self.log_debug(f"➤ SetConfigJson (guardar_config) - Tamaño: {len(json.dumps(self.config_raw))} bytes")
            response = self.cdsp.query("SetConfigJson", json.dumps(self.config_raw))
            self.log_debug(f"✓ SetConfigJson respuesta: {response}")
        except Exception as e:
            self.log_debug(f"✗ Error guardar_config: {e}")

    def marcar_fila_activa(self, fid):
        self.table.blockSignals(True)
        for r in range(self.table.rowCount()):
            it = self.table.item(r, 0)
            if it and it.text() == fid: self.table.selectRow(r); break
        self.table.blockSignals(False)

    def actualizar_celda(self, fid, col, val_str):
        self.table.blockSignals(True)
        for r in range(self.table.rowCount()):
            it = self.table.item(r, 0)
            if it and it.text() == fid:
                self.table.setItem(r, col, QTableWidgetItem(val_str)); break
        self.table.blockSignals(False)

    def enviar_parche(self, n, p):
        try:
            self.log_debug(f"➤ PatchConfig Filtro: {n}")
            payload = {"filters": {n: {"parameters": p}}}
            response = self.cdsp.query("PatchConfig", payload)
            self.log_debug(f"✓ PatchConfig respuesta: {response}")
        except Exception as e:
            self.log_debug(f"✗ Error enviar_parche: {e}")

    def crear_compresor(self, name, ch_index, threshold_db, vu_ref):
        self.log_debug(f"═══════════════════════════════════════════════��═══════════")
        self.log_debug(f"➤ CREAR COMPRESOR - INICIO")
        self.log_debug(f"  • Nombre canal: {name}")
        self.log_debug(f"  • Índice canal: {ch_index}")
        self.log_debug(f"  • Threshold: {threshold_db:.1f} dB")
        
        comp_name = f"Comp_{self.clean_name(name)}"
        self.log_debug(f"  • ID Compresor: {comp_name}")
        
        total_out_ch = self.config_raw.get("devices", {}).get("playback", {}).get("channels", len(self.v_out))
        self.log_debug(f"  • Total canales de salida: {total_out_ch}")
        
        comp_data = {
            "type": "Compressor",
            "parameters": {
                "channels": total_out_ch, "attack": 0.025, "release": 1.0,
                "threshold": float(f"{threshold_db:.1f}"), "factor": 5.0,
                "makeup_gain": 0.0, "clip_limit": 0.0, "soft_clip": True,
                "monitor_channels": [ch_index], "process_channels": [ch_index]
            }
        }
        
        self.log_debug(f"  • Datos del compresor:")
        self.log_debug(f"    {json.dumps(comp_data, indent=6)}")
        
        self.config_raw.setdefault("processors", {})[comp_name] = comp_data
        self.log_debug(f"  ✓ Compresor agregado a config_raw['processors']")
        
        # VERIFICAR PIPELINE
        self.log_debug(f"  • Buscando Processor en pipeline...")
        target = next((s for s in self.config_raw["pipeline"] if s.get("type") == "Processor" and s.get("name") == comp_name), None)
        if not target:
            target = {"type": "Processor", "name": comp_name}
            self.config_raw["pipeline"].append(target)
            self.log_debug(f"  ✓ Processor '{comp_name}' agregado al pipeline")
        else:
            self.log_debug(f"  ✓ Processor '{comp_name}' ya existe en pipeline")
        
        # ENVIAR CONFIGURACIÓN COMPLETA
        try:
            config_json = json.dumps(self.config_raw)
            self.log_debug(f"  ➤ ENVIANDO SetConfigJson...")
            self.log_debug(f"    • Tamaño JSON: {len(config_json)} bytes")
            
            response = self.cdsp.query("SetConfigJson", config_json)
            self.log_debug(f"  ✓ Respuesta CamillaDSP: {response}")
            self.log_debug(f"✓ COMPRESOR CREADO: {name} | Threshold {threshold_db:.1f} dB")
            self.log_debug(f"═══════════════════════════════════════════════════════════")
            
            vu_ref.comp_threshold = threshold_db
            vu_ref.update()
            self.actualizar_tabla_comp_ui()
            
        except Exception as e:
            self.log_debug(f"  ✗ ERROR AL ENVIAR: {type(e).__name__}: {str(e)}")
            self.log_debug(f"═══════════════════════════════════════════════════════════")
            import traceback
            self.log_debug(traceback.format_exc())

    def borrar_compresor_por_id(self, comp_name):
        self.log_debug(f"➤ BORRAR COMPRESOR: {comp_name}")
        changed = False
        if "processors" in self.config_raw and comp_name in self.config_raw["processors"]:
            del self.config_raw["processors"][comp_name]; changed = True
            self.log_debug(f"  ✓ Removido de processors")
        if "pipeline" in self.config_raw:
            new_pipe = [s for s in self.config_raw["pipeline"] if not (s.get("type") == "Processor" and s.get("name") == comp_name)]
            if len(new_pipe) != len(self.config_raw["pipeline"]):
                self.config_raw["pipeline"] = new_pipe; changed = True
                self.log_debug(f"  ✓ Removido del pipeline")
        if changed:
            try:
                self.log_debug(f"  ➤ ENVIANDO SetConfigJson...")
                response = self.cdsp.query("SetConfigJson", json.dumps(self.config_raw))
                self.log_debug(f"  ✓ Respuesta: {response}")
                self.log_debug(f"✓ COMPRESOR BORRADO: {comp_name}")
                ch_name = comp_name.replace("Comp_", "")
                for vu in self.v_out:
                    if self.clean_name(vu.name) == ch_name:
                        vu.comp_threshold = None; vu.update(); break
                self.actualizar_tabla_comp_ui()
            except Exception as e:
                self.log_debug(f"✗ Error al borrar Compresor: {e}")

    def iniciar_auto_compresion(self, pid, btn):
        ch_index = self.config_raw["processors"][pid]["parameters"]["process_channels"][0]
        self.auto_samplers[pid] = {"ticks": 100, "ch": ch_index, "history": [], "btn": btn}
        btn.setText("5s"); btn.setEnabled(False); btn.setStyleSheet("background: #aa8800; color: white; border-radius: 3px; font-weight: bold;")
        self.log_debug(f"➤ AUTO-MUESTREO {pid}: Leyendo dinámica por 5 segundos...")

    def finalizar_auto_compresion(self, pid):
        data = self.auto_samplers.pop(pid); btn = data["btn"]
        history = [x for x in data["history"] if x > -70.0]
        if not history: self.log_debug(f"AUTO-COMP {pid}: No se detectó audio en el canal. Abortado.")
        else:
            delta = max(history) - (sum(history) / len(history))
            atk, rel = (0.005, 0.05) if delta > 12.0 else (0.025, 0.25) if delta > 6.0 else (0.050, 0.50)
            self.config_raw["processors"][pid]["parameters"]["attack"] = atk
            self.config_raw["processors"][pid]["parameters"]["release"] = rel
            try:
                self.cdsp.query("SetConfigJson", json.dumps(self.config_raw))
                self.log_debug(f"AUTO-COMP {pid}: Rango dinámico {delta:.1f}dB -> Attack: {atk}s | Release: {rel}s")
                self.actualizar_tabla_comp_ui()
            except Exception as e: self.log_debug(f"Error al guardar Auto-Comp: {e}")
        try: btn.setText("AUTO"); btn.setEnabled(True); btn.setStyleSheet("background: #007bff; color: white; border-radius: 3px; font-weight: bold;")
        except: pass

    def crear_filtro_en_posicion(self, f, g):
        if self.mode == "Input":
            chs = []
            ns = []
            for d in self.sel_items:
                chs.extend([d[0], d[1]])
                ns.append(f"{self.clean_name(d[2])}_{self.clean_name(d[3])}")
            n_id = "_".join(ns)
            n_block = f"EQin_{n_id}"
            pref = "EQin"
        elif self.mode == "Output":
            chs = [x[0] for x in self.sel_items]
            ns = [self.clean_name(x[1]) for x in self.sel_items]
            n_block = f"EQout_{'_'.join(ns)}"
            pref = "EQout"
            n_id = '_'.join(ns)
        else:
            chs = [0, 1]
            n_block = "General_EQ"
            pref = "PEQ"
            n_id = "Default"

        fid = f"{pref}_{n_id}_{int(time.time())}"
        f_d = {"type": "Biquad", "parameters": {"type": "Peaking", "freq": float(f), "gain": float(g), "q": 1.0}}
        self.config_raw.setdefault("filters", {})[fid] = f_d; self.filtros_biquad[fid] = f_d
        
        if "pipeline" not in self.config_raw: self.config_raw["pipeline"] = []
        target = next((s for s in self.config_raw["pipeline"] if s.get("description") == n_block), None)
        if not target and self.mode == "Default": target = next((s for s in self.config_raw["pipeline"] if s.get("type") == "Filter"), None)
        if not target:
            target = {"type": "Filter", "description": n_block, "channels": chs, "names": []}
            if self.mode == "Input": self.config_raw["pipeline"].insert(0, target)
            else: self.config_raw["pipeline"].append(target)
        if fid not in target["names"]: target["names"].append(fid)
        self.log_debug(f"➤ Crear Filtro: {fid} @ {f:.0f}Hz, {g:.1f}dB")
        self.cdsp.query("SetConfigJson", json.dumps(self.config_raw)); self.actualizar_tabla_ui(); self.graph.update()

    def up_v(self):
        try:
            if hasattr(self.cdsp, 'levels'):
                ir = self.cdsp.levels.capture_rms(); orr = self.cdsp.levels.playback_rms()
                for i, v in enumerate(self.v_in): v.set_level(ir[i] if i < len(ir) else -80)
                for i, v in enumerate(self.v_out): v.set_level(orr[i] if i < len(orr) else -80)
                to_finish = []
                for pid, data in self.auto_samplers.items():
                    ch = data["ch"]
                    if ch < len(orr): data["history"].append(orr[ch])
                    data["ticks"] -= 1
                    if data["ticks"] % 20 == 0:
                        try: data["btn"].setText(f"{data['ticks']//20}s")
                        except: pass
                    if data["ticks"] <= 0: to_finish.append(pid)
                for pid in to_finish: self.finalizar_auto_compresion(pid)
        except: pass

    def actualizar_tabla_ui(self):
        self.table.blockSignals(True)
        self.table.setRowCount(0); tipos = ["Peaking", "Highshelf", "Lowshelf", "Highpass", "Lowpass"]
        for fid, d in self.filtros_biquad.items():
            r = self.table.rowCount(); self.table.insertRow(r); p = d["parameters"]
            it = QTableWidgetItem(fid); it.setFlags(it.flags() & ~Qt.ItemIsEditable); self.table.setItem(r, 0, it)
            cb = QComboBox(); cb.addItems(tipos); cb.setCurrentText(p["type"])
            cb.currentTextChanged.connect(lambda t, f=fid: self.cambiar_tipo(f, t))
            self.table.setCellWidget(r, 1, cb)
            self.table.setItem(r, 2, QTableWidgetItem(f"{p['freq']:.0f}"))
            gv = f"{p.get('gain',0):.1f}" if "gain" in p else "0.0"; self.table.setItem(r, 3, QTableWidgetItem(gv))
            self.table.setItem(r, 4, QTableWidgetItem(f"{p.get('q',1.0):.2f}"))
            btn = QPushButton("X"); btn.clicked.connect(lambda ch, f=fid: self.borrar(f)); self.table.setCellWidget(r, 5, btn)
        self.table.blockSignals(False)

    def modificar_filtro_desde_tabla(self, item):
        r = item.row(); c = item.column()
        if c not in [2, 3, 4]: return
        fid = self.table.item(r, 0).text()
        try: val = float(item.text())
        except ValueError: return
        keys = {2: "freq", 3: "gain", 4: "q"}; param = keys[c]
        if fid in self.filtros_biquad:
            self.filtros_biquad[fid]["parameters"][param] = val
            try: self.cdsp.query("SetConfigJson", json.dumps(self.config_raw)); self.graph.update()
            except: pass

    def actualizar_tabla_comp_ui(self):
        self.comp_table.blockSignals(True)
        self.comp_table.setRowCount(0)
        processors = self.config_raw.get("processors", {})
        for pid, pdata in processors.items():
            if pdata.get("type") == "Compressor":
                r = self.comp_table.rowCount(); self.comp_table.insertRow(r); params = pdata.get("parameters", {})
                it_id = QTableWidgetItem(pid); it_id.setFlags(it_id.flags() & ~Qt.ItemIsEditable); self.comp_table.setItem(r, 0, it_id)
                self.comp_table.setItem(r, 1, QTableWidgetItem(str(params.get("attack", 0.025))))
                self.comp_table.setItem(r, 2, QTableWidgetItem(str(params.get("release", 1.0))))
                self.comp_table.setItem(r, 3, QTableWidgetItem(str(params.get("threshold", -20.0))))
                self.comp_table.setItem(r, 4, QTableWidgetItem(str(params.get("factor", 5.0))))
                self.comp_table.setItem(r, 5, QTableWidgetItem(str(params.get("makeup_gain", 0.0))))
                self.comp_table.setItem(r, 6, QTableWidgetItem(str(params.get("clip_limit", 0.0))))
                btn_auto = QPushButton("AUTO")
                if pid in self.auto_samplers:
                    btn_auto.setText(f"{self.auto_samplers[pid]['ticks']//20}s")
                    btn_auto.setEnabled(False); btn_auto.setStyleSheet("background: #aa8800; color: white; border-radius: 3px; font-weight: bold;")
                else:
                    btn_auto.setStyleSheet("background: #007bff; color: white; border-radius: 3px; font-weight: bold;")
                    btn_auto.clicked.connect(lambda ch, f=pid, b=btn_auto: self.iniciar_auto_compresion(f, b))
                self.comp_table.setCellWidget(r, 7, btn_auto)
                btn_del = QPushButton("X"); btn_del.clicked.connect(lambda ch, f=pid: self.borrar_compresor_por_id(f))
                self.comp_table.setCellWidget(r, 8, btn_del)
        self.comp_table.blockSignals(False)

    def modificar_compresor_desde_tabla(self, item):
        r = item.row(); c = item.column()
        if c == 0 or c == 7 or c == 8: return
        pid = self.comp_table.item(r, 0).text()
        try: val = float(item.text())
        except ValueError: return
        keys = ["", "attack", "release", "threshold", "factor", "makeup_gain", "clip_limit"]; param = keys[c]
        if pid in self.config_raw.get("processors", {}):
            self.config_raw["processors"][pid]["parameters"][param] = val
            if param == "threshold":
                ch_name = pid.replace("Comp_", "")
                for vu in self.v_out:
                    if self.clean_name(vu.name) == ch_name:
                        vu.comp_threshold = val; vu.update(); break
            try:
                self.log_debug(f"➤ Compresor {pid} actualizado: {param} = {val}")
                self.cdsp.query("SetConfigJson", json.dumps(self.config_raw))
                self.log_debug(f"✓ Compresor {pid} actualizado: {param} = {val}")
            except Exception as e:
                self.log_debug(f"✗ Error: {e}")

    def cambiar_tipo(self, fid, nt):
        if fid in self.filtros_biquad:
            self.filtros_biquad[fid]["parameters"]["type"] = nt
            self.cdsp.query("SetConfigJson", json.dumps(self.config_raw)); self.graph.update()

    def borrar(self, fid):
        if fid in self.filtros_biquad:
            del self.filtros_biquad[fid]; del self.config_raw["filters"][fid]
            for s in self.config_raw.get("pipeline", []):
                if s.get("type") == "Filter" and "names" in s:
                    s["names"] = [n for n in s["names"] if n != fid]
            self.cdsp.query("SetConfigJson", json.dumps(self.config_raw)); self.actualizar_tabla_ui(); self.graph.update()

if __name__ == "__main__":
    app = QApplication(sys.argv); window = PEQApp(); window.show(); sys.exit(app.exec())