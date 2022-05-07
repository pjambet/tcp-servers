exit if fork

p Process.pid

# Create a new session, create a new child process in it and 
# exit the current process. 
Process.setsid
exit if fork

p Process.pid

exec("yes &> /dev/null")
