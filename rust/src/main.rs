// extern crate libc;

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
    let mut vec: Vec<TcpStream> = Vec::new();
    let mut streams: Vec<&TcpStream> = Vec::new();
    let mut stream_ref: &TcpStream;

    let listener = TcpListener::bind("127.0.0.1:7878").unwrap();
    let raw_fd = listener.as_raw_fd();

    let mut max_fd = raw_fd;

    let mut db: HashMap<String, String> = HashMap::from([("abc".to_string(), "123".to_string()), ("def".to_string(), "456".to_string())]);

    let mut client1: Option<TcpStream> = None;
    let mut client3: Option<TcpStream> = None;
    let mut client2: Option<TcpStream> = None;

    loop {
        streams.clear();
        let mut new_client: bool = false;
        fd_set.set(raw_fd);
        for s in vec.iter() {
            println!("In vec: {}", s.as_raw_fd());
            fd_set.set(s.as_raw_fd());
        }
        match client1 {
            Some(s) => {
                fd_set.set(s.as_raw_fd());
                client1 = Some(s);
            }
            None => {}
        }
        match client2 {
            Some(s) => {
                fd_set.set(s.as_raw_fd());
                client2 = Some(s);
            }
            None => {}
        }
        match client3 {
            Some(s) => {
                fd_set.set(s.as_raw_fd());
                client3 = Some(s);
            }
            None => {}
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
                let range = std::ops::Range {
                    start: 0,
                    end: max_fd + 1,
                };
                for i in range {
                    if (fd_set).is_set(i) {
                        println!("Socket {} received something!", i);
                        if i == raw_fd {
                            new_client = true
                        }
                        // for v in vec.iter() {
                        //     if i == v.as_raw_fd() {
                        //         println!("Found stream");
                        //         streams.push(&v);
                        //     }
                        // }
                    }
                    // fd_set.clear(i);
                }
                if new_client {
                    let stream = listener.accept().unwrap().0;
                    let stream_fd = stream.as_raw_fd();
                    if client1.is_none() {
                        client1 = Some(stream)
                    } else if client2.is_none() {
                        client2 = Some(stream)
                    } else if client3.is_none() {
                        client3 = Some(stream)
                    } else {
                        println!("Reached max limit of connected clients")
                    }
                    fd_set.set(stream_fd);
                    if stream_fd > max_fd {
                        max_fd = stream_fd;
                    }
                    println!("stream: {}", stream_fd);
                    println!("new max: {}", max_fd);
                    // vec.push(stream);
                } else {
                    println!("Handling a request from a client");
                    // for s in vec.iter() {
                    match client1 {
                        Some(s) => {
                            if fd_set.is_set(s.as_raw_fd()) {
                                fd_set.clear(s.as_raw_fd());
                                let tuple = handle_connection(s, db);
                                db = tuple.1;
                                client1 = Some(tuple.0);
                            } else {
                                client1 = Some(s)
                            }
                        }
                        None => {}
                    }
                    match client2 {
                        Some(s) => {
                            if fd_set.is_set(s.as_raw_fd()) {
                                fd_set.clear(s.as_raw_fd());
                                let tuple = handle_connection(s, db);
                                db = tuple.1;
                                client2 = Some(tuple.0);
                            } else {
                                client2 = Some(s);
                            }
                        }
                        None => {}
                    }
                    match client3 {
                        Some(s) => {
                            if fd_set.is_set(s.as_raw_fd()) {
                                fd_set.clear(s.as_raw_fd());
                                let tuple = handle_connection(s, db);
                                db = tuple.1;
                                client3 = Some(tuple.0);
                            } else {
                                client3 = Some(s);
                            }
                        }
                        None => {}
                    }
                }
            }
            Err(err) => {
                println!("Failed to select: {}", err);
            }
        }
    }
}

fn handle_connection<'a>(
    mut stream: TcpStream,
    mut db: HashMap<String, String>,
) -> (TcpStream, HashMap<String, String>) {
    let mut buffer = [0; 1024];
    stream.read(&mut buffer).unwrap();
    let request = String::from_utf8_lossy(&buffer);
    println!("Received: {}", request);
    // for b in buffer {
    //     println!("b: {}", b);
    // }
    let s: String;
    // let new_db = db.clone();

    let response = if request.starts_with("GET") {
        let parts: Vec<&str> = request.split(|c| char::is_ascii_whitespace(&c)).collect();
        if parts.len() > 1 {
            println!("key: '{}'", parts[1]);
            println!("key.len: '{}'", parts[1].len());
            let key = parts[1];
            println!("key=abc: {}", key == "abc");
            // for (key, value) in db {
            //     println!("'{}': '{}'", key, value);
            // }
            s = match db.get(key) {
                Some(res) => {
                    // s = Some(res);
                    res.to_string()
                },
                None => "".to_string(),
            };
            println!("s: {}", s);
            s
        } else {
            "N/A\n".to_string()
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
            // for (key, value) in db {
            //     println!("'{}': '{}'", key, value);
            // }
            db.insert(key.to_string(), value.to_string());
            // db.insert(key.clone().to_owned().as_str(), value.parse::<i32>().unwrap().clone());
            // println!("s: {}", s);
            "OK\n".to_string()
        } else {
            "N/A\n".to_string()
        }
    } else {
        "OK\n".to_string()
    };

    stream.write(response.as_bytes()).unwrap();
    stream.flush().unwrap();

    (stream, db)
}
