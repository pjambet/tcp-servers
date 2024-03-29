use std::collections::HashMap;
use std::io::prelude::*;
use std::net::{TcpListener, TcpStream};
use std::os::unix::io::{AsRawFd, RawFd};
use std::{io, mem, ptr, str, time};

pub struct FdSet(libc::fd_set);

impl FdSet {
    pub fn new() -> FdSet {
        unsafe {
            let mut raw_fd_set = mem::MaybeUninit::<libc::fd_set>::uninit();
            libc::FD_ZERO(raw_fd_set.as_mut_ptr());
            FdSet(raw_fd_set.assume_init())
        }
    }
    pub fn clear(&mut self, fd: RawFd) {
        unsafe { libc::FD_CLR(fd, &mut self.0) }
    }
    pub fn set(&mut self, fd: RawFd) {
        unsafe { libc::FD_SET(fd, &mut self.0) }
    }
    pub fn is_set(&mut self, fd: RawFd) -> bool {
        unsafe { libc::FD_ISSET(fd, &mut self.0) }
    }
}

fn to_fdset_ptr(opt: Option<&mut FdSet>) -> *mut libc::fd_set {
    match opt {
        None => ptr::null_mut(),
        Some(&mut FdSet(ref mut raw_fd_set)) => raw_fd_set,
    }
}
fn to_ptr<T>(opt: Option<&T>) -> *const T {
    match opt {
        None => ptr::null::<T>(),
        Some(p) => p,
    }
}

pub fn select(
    nfds: libc::c_int,
    readfds: Option<&mut FdSet>,
    writefds: Option<&mut FdSet>,
    errorfds: Option<&mut FdSet>,
    timeout: Option<&libc::timeval>,
) -> io::Result<usize> {
    match unsafe {
        libc::select(
            nfds,
            to_fdset_ptr(readfds),
            to_fdset_ptr(writefds),
            to_fdset_ptr(errorfds),
            to_ptr::<libc::timeval>(timeout) as *mut libc::timeval,
        )
    } {
        -1 => Err(io::Error::last_os_error()),
        res => Ok(res as usize),
    }
}

pub fn make_timeval(duration: time::Duration) -> libc::timeval {
    libc::timeval {
        tv_sec: duration.as_secs() as i64,
        tv_usec: duration.subsec_micros() as i32,
    }
}

fn main() {
    let mut fd_set = FdSet::new();
    let mut clients: HashMap<i32, TcpStream> = HashMap::from([]);

    let listener = TcpListener::bind("127.0.0.1:3000").unwrap();
    let raw_fd = listener.as_raw_fd();

    let mut max_fd = raw_fd;

    let mut db: HashMap<String, String> = HashMap::from([]);

    loop {
        fd_set.set(raw_fd);
        for (fd, _) in &clients {
            println!("In vec: {}", fd);
            fd_set.set(*fd);
        }
        match select(
            max_fd + 1,
            Some(&mut fd_set),
            None,
            None,
            Some(&make_timeval(time::Duration::new(10, 0))),
        ) {
            Ok(res) => {
                println!("select result: {}", res);
                println!("raw: {}", raw_fd);

                if fd_set.is_set(raw_fd) {
                    let stream = listener.accept().unwrap().0;
                    let stream_fd = stream.as_raw_fd();
                    fd_set.set(stream_fd);
                    fd_set.clear(raw_fd);
                    if stream_fd > max_fd {
                        max_fd = stream_fd;
                    }
                    println!("stream: {}", stream_fd);
                    println!("new max: {}", max_fd);
                    clients.insert(stream.as_raw_fd(), stream);
                } else {
                    println!("Handling a request from a client");
                    let range = std::ops::Range {
                        start: 0,
                        end: max_fd + 1,
                    };
                    for i in range {
                        if i != raw_fd && (fd_set).is_set(i) {
                            fd_set.clear(i);
                            let stream = clients.get(&i).unwrap();
                            if handle_connection(stream, &mut db) == false {
                                clients.remove(&i);
                            }

                            println!("Socket {} received something!", i);
                        }
                    }
                }
            }
            Err(err) => {
                println!("Failed to select: {}", err);
            }
        }
    }
}

fn handle_connection(mut stream: &TcpStream, db: &mut HashMap<String, String>) -> bool {
    let mut buffer = [0; 1024];
    let read_result = stream.read(&mut buffer);
    if read_result.is_err() {
        return false;
    }
    read_result.unwrap();
    let request = String::from_utf8_lossy(&buffer);
    println!("Received: {}", request);

    let response = if request.starts_with("GET") {
        let parts: Vec<&str> = request.split(|c| char::is_ascii_whitespace(&c)).collect();
        if parts.len() > 1 {
            println!("key: '{}'", parts[1]);
            println!("key.len: '{}'", parts[1].len());
            let key = parts[1];
            println!("key=abc: {}", key == "abc");

            match db.get(key) {
                Some(res) => res.to_string() + "\n",
                None => "\n".to_string(),
            }
        } else {
            "\n".to_string()
        }
    } else if request.starts_with("SET") {
        let parts: Vec<&str> = request.split(|c| char::is_ascii_whitespace(&c)).collect();
        println!("SET request");
        if parts.len() > 2 {
            println!("key: '{}'", parts[1]);
            println!("key.len: '{}'", parts[1].len());
            let key = parts[1];
            let value = parts[2];
            println!("key=abc: {}", key == "abc");
            db.insert(key.to_string(), value.to_string());
            "OK\n".to_string()
        } else {
            "\n".to_string()
        }
    } else if request.starts_with("DEL") {
        let parts: Vec<&str> = request.split(|c| char::is_ascii_whitespace(&c)).collect();
        if parts.len() > 2 {
            let key = parts[1];
            if db.contains_key(key) {
                db.remove(key);
                "1\n".to_string()
            } else {
                "0\n".to_string()
            }
        } else {
            "\n".to_string()
        }
    } else if request.starts_with("INCR") {
        let parts: Vec<&str> = request.split(|c| char::is_ascii_whitespace(&c)).collect();
        if parts.len() > 2 {
            let key = parts[1];
            match db.get(key) {
                Some(existing_string) => match existing_string.parse::<i32>() {
                    Ok(existing_int) => {
                        let new_value = existing_int + 1;
                        db.insert(key.to_string(), new_value.to_string());
                        new_value.to_string() + "\n"
                    }
                    Err(_err) => "ERR value is not an integer or out of range\n".to_string(),
                },
                None => {
                    db.insert(key.to_string(), "1".to_string());
                    "1\n".to_string()
                }
            }
        } else {
            "\n".to_string()
        }
    } else if request.starts_with("QUIT") {
        return false;
    } else {
        "OK\n".to_string()
    };

    let write_response = stream.write(response.as_bytes());
    if write_response.is_err() {
        return false;
    }
    write_response.unwrap();
    stream.flush().unwrap();

    return true;
}
