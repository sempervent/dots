package main

deny contains msg if {
  input.allowed == false
  msg := "allowed must be true"
}