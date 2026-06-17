import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.Map;

class Syntax {

    static void main() {
        int[] nums = {0,1,1,1,2,2,3,3,4};
        removeDuplicates(nums);
        System.out.println(Arrays.toString(nums));
    }

    public static int removeDuplicates(int[] nums) {
        int index = 1;

        int duplicateIndex = 1;

        while (index  < nums.length) {
            if (nums[index] != nums[index - 1]){
                swap(nums, duplicateIndex, index);
                duplicateIndex++;
            }

            index++;
        }

        return nums.length;
    }

    public static void swap (int[] nums, int a, int b) {
        int temp = nums[a];
        nums[a] = nums[b];
        nums[b] = temp;
    }
}
