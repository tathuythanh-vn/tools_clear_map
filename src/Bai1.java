import java.util.*;

// https://leetcode.com/problems/two-sum/description/
public class Bai1 {

    public static void main(String[] args) {
        int[] nums = {2, 7, 11, 15};
        int target = 9;
        System.out.println(Arrays.toString(Solution(nums, target)));
    }

    public static int[] Solution(int[] nums, int target) {
        // Create a hash map
        Map<Integer, Integer> checkedNums = new HashMap<>();

        for (int i = 0; i < nums.length; i++) {

            // if (target - x) not in hash map --> add
            if (checkedNums.containsKey(target - nums[i])) {
                return new int[]{i, checkedNums.get(target - nums[i])};
            } else {
                checkedNums.put(nums[i], i);
            }
        }

        return nums;
    }
}
