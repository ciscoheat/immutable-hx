@echo off
del immutable.zip >nul 2>&1

cd src
copy ..\README.md .
zip -r ..\immutable.zip .
del README.md
cd ..

haxelib submit immutable.zip
del immutable.zip
