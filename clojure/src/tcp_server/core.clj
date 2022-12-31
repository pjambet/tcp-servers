(ns tcp-server.core
  (:require [clojure.core.async
             :as a
             :refer [<! >! chan go]]
            [clojure.java.io
             :as io]
            [clojure.string
             :as string])
  (:import (java.net ServerSocket))
  (:gen-class))

(defn key-request
  [type key channel]
  {:type type :key key :resp channel})

(defn key-value-request
  [type key value channel]
  (assoc (key-request type key channel) :value value))

(def valid-commands
  #{"GET" "SET" "INCR" "DEL"})

(defn request-for-command
  [command parts resp-channel]
  (cond
    (= command "GET")
    (key-request :get (get parts 1) resp-channel)
    (= command "SET")
    (key-value-request :set (get parts 1) (get parts 2) resp-channel)
    (= command "INCR")
    (key-request :incr (get parts 1) resp-channel)
    (= command "DEL")
    (key-request :del (get parts 1) resp-channel)))


(defn handle-client
  " write me ..."
  [channel client-socket]
  (go (loop [resp-channel (chan)]
        (let [request (.readLine (io/reader client-socket))
              writer (io/writer client-socket)
              parts (string/split request #" ")
              command (get parts 0)]
          (cond
            (contains? valid-commands command)
            (let [response (request-for-command command parts resp-channel)]
              (when response
                (>! channel response)
                (let [value (<! resp-channel)]
                  (.write writer (str value "\n"))
                  (.flush writer)
                  (recur resp-channel))))
            (= command "QUIT") (.close client-socket)
            :else (do
                    (println "Unknown request:" request)
                    (recur resp-channel)))))))

(defn atoi
  [string]
  (try
    (Integer. string)
    (catch NumberFormatException _e
      nil)))

(defn update-db
  [db command key value]
  (cond
    (= command :get)
    (if key
      (let [value (get db key "")]
        {:updated db :response value})
      {:updated db :response "ERR wrong number of arguments for 'get' command"})
    (= command :set)
    (if (and key value)
      {:updated (assoc db key value) :response "OK"}
      {:updated db :response "ERR wrong number of arguments for 'set' command"})
    (= command :del)
    (if key
      (if (contains? db key)
        {:updated (dissoc db key) :response "1"}
        {:updated db :response "0"})
      {:updated db :response "ERR wrong number of arguments for 'del' command"})
    (= command :incr)
    (if key
      (if (contains? db key)
        (let [number (atoi (get db key))]
          (if number
            {:updated (assoc db key (str (+ number 1))) :response (str (+ number 1))}
            {:updated db :response "ERR value is not an integer or out of range"}))
        {:updated (assoc db key "1") :response "1"})
      {:updated db :response "ERR wrong number of arguments for 'incr' command"})
    :else {:updated db :response "Unknown command"}))

(defn -main
  "I don't do a whole lot ... yet."
  [& _args]
  (println "About to start ...")
  (let [command-channel (chan)]
    (go (loop [db (hash-map)]
          (let [response (<! command-channel)
                type (response :type)
                key (response :key)
                value (response :value)
                chan-resp (response :resp)
                result (update-db db type key value)
                new-db (result :updated)
                response (result :response)]
            (>! chan-resp response)
            (recur new-db))))
    (with-open [server-socket (ServerSocket. 3000)]
      (loop []
        (let [client-socket (.accept server-socket)]
          (handle-client command-channel client-socket))
        (recur)))))
