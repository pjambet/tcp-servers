(ns tcp-server.core
  (:require [clojure.core.async :as a]
            [clojure.java.io :as io]
            [clojure.string :as string])
  (:import (java.net ServerSocket))
  (:gen-class))

(defn key-request
  "Helper to structure the basic parts of a command"
  [command key]
  {:command command :key key})

(defn key-value-request
  "Helper to structure the various parts of a SET command"
  [command key value]
  (assoc (key-request command key) :value value))

(def valid-commands
  "Valid commands"
  #{"GET" "SET" "INCR" "DEL"})

(defn request-for-command
  "Return a structured representation of a client command"
  [command parts]
  (cond
    (= command "GET")
    (key-request :get (get parts 1))
    (= command "SET")
    (key-value-request :set (get parts 1) (get parts 2))
    (= command "INCR")
    (key-request :incr (get parts 1))
    (= command "DEL")
    (key-request :del (get parts 1))))


(defn atoi
  "Attempt to convert a string to integer, returns nil if it can't be parsed"
  [string]
  (try
    (Integer/valueOf string)
    (catch NumberFormatException _e
      nil)))

(defn increment-number
  "Wrap the lower level operations required to process an increment command"
  [db key]
  (swap! db (fn [current-state]
              (if (contains? current-state key)
                (let [number (atoi (get current-state key))]
                  (if number
                    (assoc current-state key (str (+ number 1)))
                    current-state))
                (assoc current-state key "1")))))

(defn process-command
  "Perform various operations depending on the command sent by the client"
  [db request]
  (let [command (request :command)
        key (request :key)
        value (request :value)]
    (cond
      (= command :get)
      (if key
        (get @db key "")
        "ERR wrong number of arguments for 'get' command")
      (= command :set)
      (if (and key value)
        (do
          (swap! db (fn [current-state]
                      (assoc current-state key value)))
          "OK")
        "ERR wrong number of arguments for 'set' command")
      (= command :del)
      (if key
        (let [[old-value _] (swap-vals! db (fn [current-state]
                                             (dissoc current-state key)))]
          (if (contains? old-value key) "1" "0"))
        "ERR wrong number of arguments for 'del' command")
      (= command :incr)
      (if key
        (let [new-value (increment-number db key)
              number (atoi (get new-value key))]
          (if number
            number
            "ERR value is not an integer or out of range"))
        "ERR wrong number of arguments for 'incr' command")
      :else "Unknown command")))

(defn handle-client
  "Read from a connected client, and handles the various commands accepted by the server"
  [client-socket db]
  (a/go (loop []
          (let [request (.readLine (io/reader client-socket))
                writer (io/writer client-socket)]
            (if (nil? request)
              (do
                (println "Nil request, closing")
                (.close client-socket))
              (let [parts (string/split request #" ")
                    command (get parts 0)]
                (cond
                  (contains? valid-commands command)
                  (let [request (request-for-command command parts)
                        value (process-command db request)]
                    (.write writer (str value "\n"))
                    (.flush writer)
                    (recur))
                  (= command "QUIT")
                  (.close client-socket)
                  :else (do
                          (println "Unknown request:" request)
                          (recur)))))))))

(defn -main
  "Start a server and continuously wait for new clients to connect"
  [& _args]
  (println "About to start ...")
  (let [db (atom {})]
    (with-open [server-socket (ServerSocket. 3000)]
      (loop []
        (let [client-socket (.accept server-socket)]
          (handle-client client-socket db))
        (recur)))))
