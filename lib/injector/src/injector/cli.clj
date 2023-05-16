(ns injector.cli
  (:require [clojure.edn :as edn]
            [clojure.pprint :refer [pprint]]
            [clojure.string :as str]
            [clojure.tools.cli :refer [parse-opts]]
            [injector.core :refer [inject-dependencies]])
  (:gen-class))

(def cli-opts
  [[nil "--deps-file DEPS_FILE" "Source deps.edn file."]])

(defn- usage [summary errors]
  (->> (concat errors ["usage: injector [opts] [[<library> <jar-file>] ...]"
                       ""
                       "Options:"
                       summary])
       (str/join \newline)))

(defn -main [& args]
  (let [{:keys [options args errors summary]} (parse-opts args cli-opts)
        inj-deps (into {} (partition 2 args))]
    (when (seq errors) (usage summary errors))
    (when (not (contains? options :deps-file))
      (usage summary ["missing required argument: deps-file"]))
    (println (format "replacing: %s" inj-deps))
    (let [deps (-> options :deps-file (slurp) (edn/read-string))]
      (pprint (inject-dependencies deps inj-deps)))
    (System/exit 0)))
