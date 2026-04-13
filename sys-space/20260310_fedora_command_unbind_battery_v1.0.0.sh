#!/bin/bash

if zenity --question --title="Unbind Battery Driver" --text="Do you want to unbind the battery driver now?"; then
    echo PNP0C0A:01 | sudo tee /sys/bus/acpi/drivers/battery/unbind
    zenity --info --text="Battery driver unbound successfully."
else
    zenity --info --text="Skipped unbinding the battery driver."
fi
