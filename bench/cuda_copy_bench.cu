/**
 * Copyright 2018-present Antonio Mallia <me@antoniomallia.it>
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#include <gmock/gmock.h>
#include <gtest/gtest.h>
#include "synthetic/uniform.hpp"
#include "benchmark/benchmark.h"

#include "bp/cuda_copy.cuh"
#include "bp/cuda_common.hpp"


#include <cuda.h>

__global__
void warmUpGPU()
{
  // do nothing
}

class RandomValuesFixture : public ::benchmark::Fixture {

    static std::vector<uint32_t> generate_random_vector(size_t n) {
        std::random_device rd;
        std::mt19937 gen(rd());
        std::vector<uint32_t> values(n);
        std::uniform_int_distribution<> dis(uint32_t(0));
        std::generate(values.begin(), values.end(), [&](){ return dis(gen); });
        return values;
    }

public:
    using ::benchmark::Fixture::SetUp;
    using ::benchmark::Fixture::TearDown;

    virtual void SetUp(::benchmark::State& st) {
        values = generate_random_vector(st.range(0));
        CUDA_CHECK_ERROR(cudaMallocHost((void**)&pinned_encoded, values.size() * sizeof(uint32_t)));
        memcpy(pinned_encoded, values.data(), values.size() * sizeof(uint32_t));

        decoded_values.resize(values.size());
        CUDA_CHECK_ERROR(cudaSetDevice(3));
        warmUpGPU<<<1, 1>>>();

    }

    virtual void TearDown(::benchmark::State&) {
        ASSERT_EQ(decoded_values.size(), values.size());
        for (size_t i = 0; i < values.size(); ++i)
        {
            ASSERT_EQ(decoded_values[i], values[i]);

        }
        values.clear();
        decoded_values.clear();
    }
    std::vector<uint32_t> values;
    uint32_t* pinned_encoded;
    std::vector<uint32_t> decoded_values;
};


BENCHMARK_DEFINE_F(RandomValuesFixture, decode)(benchmark::State& state) {
    while (state.KeepRunning()) {
        cuda_copy::decode(decoded_values.data(), reinterpret_cast<uint8_t*>(pinned_encoded), decoded_values.size());
    }
    auto bpi = 32;
    state.counters["bpi"] = benchmark::Counter(bpi, benchmark::Counter::kAvgThreads);
}
BENCHMARK_REGISTER_F(RandomValuesFixture, decode)->Range(1ULL<<14, 1ULL<<28);

BENCHMARK_MAIN();
