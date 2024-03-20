(ns build-injector.cli
  (:require [clojure.edn :as edn]
            [clojure.pprint :refer [pprint]]
            [clojure.string :as str]
            [clojure.tools.cli :refer [parse-opts]]
            [build-injector.core :refer [inject-build-dependencies
                                         inject-build-namespace]])
  (:gen-class))

(def cli-opts
  [[nil "--deps-file DEPS_FILE" "Source deps.edn file."]
   [nil "--build-namespace NAMESPACE" "Namespace in which to find build functions."]])

(defn- usage [summary errors]
  (->> (concat errors ["usage: injector [opts] [[<library> <jar-file>] ...]"
                       ""
                       "Options:"
                       summary])
       (str/join \newline)))

(defn -main [& args]
  (let [{:keys [options arguments errors summary]} (parse-opts args cli-opts)
        inj-deps (into {} (for [[k v] (partition 2 arguments)] [(symbol k) v]))]
    (when (seq errors)
      (.println *err* (usage summary errors))
      (System/exit 1))
    (when (not (contains? options :deps-file))
      (.println *err* (usage summary ["missing required argument: deps-file"]))
      (System/exit 1))
    (when (not (contains? options :build-namespace))
      (.println *err* (usage summary ["missing required argument: build-namespace"])))
    (let [deps (-> options :deps-file (slurp) (edn/read-string))]
      (pprint (-> deps
                  (inject-build-dependencies inj-deps)
                  (inject-build-namespace (:build-namespace options)))))
    (System/exit 0)))
