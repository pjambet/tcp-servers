(ns tcp-server.core
  (:import (java.net ServerSocket))
  (:require [clojure.core.async
             :as a
             :refer [>! <! >!! <!! go chan buffer close! thread
                     alts! alts!! timeout]]
            [clojure.java.io
             :as io])
  (:gen-class))

(defn get-request
  [request]
  (let [parts (clojure.string/split request #" ")
        key (get parts 1)]
    {:type :get :key key :resp (chan)}))

(defn set-request
  [request]
  (let [parts (clojure.string/split request #" ")
        key (get parts 1)
        value (get parts 2)]
    {:type :set :key key :value value}))

(defn handle-client
  " write me ..."
  [channel client-socket]
  (go (loop []
        (let [request (.readLine (io/reader client-socket))
              writer (io/writer client-socket)]
          (cond
            (clojure.string/starts-with? request "GET") (let [response (get-request request)
                                                              resp-channel (response :resp)]
                                                          (>! channel response)
                                                          (let [value (<! resp-channel)]
                                                            (.write writer (str value "\n"))
                                                            (.flush writer)))
            (clojure.string/starts-with? request "SET") (let [response (set-request request)]
                                                          (>! channel response)
                                                          (.write writer "OK\n")
                                                          (.flush writer))
            :else (println "Unknown request:" request))
          (recur)))))


(defn -main
  "I don't do a whole lot ... yet."
  [& args]
  (println "About to start ...")
  (let [c1 (chan)]
    (go (loop [db (hash-map)]
          (let [response (<! c1)
                type (response :type)
                key (response :key)
                value (response :value)
                chan-resp (response :resp)]
            (cond
              (= type :get) (do
                              (>! chan-resp (get db key "N/A"))
                              (recur db))
              (= type :set) (do
                              (println "setting value")
                              (recur (assoc db key value)))
              :else (println "unknown query type")))))
    (with-open [server-socket (ServerSocket. 3000)]
      (loop []
        (let [client-socket (.accept server-socket)]
          (handle-client c1 client-socket))
        (recur)))))
