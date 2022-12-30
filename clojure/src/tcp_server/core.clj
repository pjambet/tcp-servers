(ns tcp-server.core
  (:require [clojure.core.async
             :as a
             :refer [<! >! chan go]]
            [clojure.java.io
             :as io]
            [clojure.string
             :as clojure.string])
  (:import (java.net ServerSocket))
  (:gen-class))

(defn get-request
  [parts]
  (let [key (get parts 1)]
    {:type :get :key key :resp (chan)}))

(defn set-request
  [parts]
  (let [key (get parts 1)
        value (get parts 2)]
    {:type :set :key key :value value :resp (chan)}))

(defn del-request
  [parts]
  (let [key (get parts 1)]
    {:type :del :key key :resp (chan)}))

(defn incr-request
  [parts]
  (let [key (get parts 1)]
    {:type :incr :key key :resp (chan)}))

(defn handle-client
  " write me ..."
  [channel client-socket]
  (go (loop []
        (let [request (.readLine (io/reader client-socket))
              writer (io/writer client-socket)
              parts (clojure.string/split request #" ")
              command (get parts 0)]
          (cond
            (= command "GET") (let [response (get-request parts)
                                    resp-channel (response :resp)]
                                (>! channel response)
                                (let [value (<! resp-channel)]
                                  (.write writer (str value "\n"))
                                  (.flush writer)
                                  (recur)))
            (= command "SET") (let [response (set-request parts)
                                    resp-channel (response :resp)]
                                (>! channel response)
                                (let [value (<! resp-channel)]
                                  (.write writer (str value "\n"))
                                  (.flush writer)
                                  (recur)))
            (= command "DEL") (let [response (del-request parts)
                                    resp-channel (response :resp)]
                                (>! channel response)
                                (let [value (<! resp-channel)]
                                  (.write writer (str value "\n"))
                                  (.flush writer)
                                  (recur)))
            (= command "INCR") (let [response (incr-request parts)
                                     resp-channel (response :resp)]
                                 (>! channel response)
                                 (let [value (<! resp-channel)]
                                   (.write writer (str value "\n"))
                                   (.flush writer)
                                   (recur)))
            (= command "QUIT") (.close client-socket)
            :else (do
                    (println "Unknown request:" request)
                    (recur)))))))

(defn atoi
  [string]
  (try
    (Integer. string)
    (catch NumberFormatException _e
      nil)))

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
                chan-resp (response :resp)]
            (cond
              (= type :get) (do
                              (>! chan-resp (get db key ""))
                              (recur db))
              (= type :set) (if value
                              (do
                                (>! chan-resp "OK")
                                (recur (assoc db key value)))
                              (do
                                (>! chan-resp "ERR wrong number of arguments for 'set' command")
                                (recur db)))
              (= type :del) (if key
                              (if (contains? db key)
                                (do
                                  (>! chan-resp "1")
                                  (recur (dissoc db key)))
                                (do
                                  (>! chan-resp "0")
                                  (recur db)))
                              (do
                                (>! chan-resp "ERR wrong number of arguments for 'del' command")
                                (recur db)))
              (= type :incr) (if key
                               (if (contains? db key)
                                 (let [number (atoi (get db key))]
                                   (if number
                                     (do
                                       (>! chan-resp (str (+ number 1)))
                                       (recur (assoc db key (str (+ number 1)))))
                                     (do
                                       (>! chan-resp "ERR value is not an integer or out of range")
                                       (recur db))))
                                 (do
                                   (println "missing")
                                   (>! chan-resp "1")
                                   (recur (assoc db key "1"))))
                               (do
                                 (>! chan-resp "ERR wrong number of arguments for 'incr' command")
                                 (recur db)))
              :else (do
                      (println "unknown query type")
                      (recur db))))))
    (with-open [server-socket (ServerSocket. 3000)]
      (loop []
        (let [client-socket (.accept server-socket)]
          (handle-client command-channel client-socket))
        (recur)))))
