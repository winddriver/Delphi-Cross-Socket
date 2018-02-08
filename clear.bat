@echo off
for /d /r %%f in (__history;__recovery;*.log) do rmdir /s/q %%f
for /r %%f in (*.dcu;*.drc;*.map;*.o;*.log) do del /f/q %%f
