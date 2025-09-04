#!/bin/bash
# Se ejecuta con usuario root por lo que no necesita sudo

# Crear usuario sin login para la app
useradd -r -s /bin/false flaskuser

# Clonar la app
cd /home
git clone https://github.com/warleon/cloud-computing-tarea-1.git
chown -R flaskuser:flaskuser cloud-computing-tarea-1

# Instalar el servicio systemd
cd cloud-computing-tarea-1/app
chmod +x start_app.sh
cp flaskapp.service /etc/systemd/system/flaskapp.service

# Habilitar y arrancar el servicio
systemctl daemon-reload
systemctl enable flaskapp.service
systemctl start flaskapp.service
